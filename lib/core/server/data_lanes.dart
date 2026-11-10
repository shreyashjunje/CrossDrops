import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../log.dart';
import '../protocol/models.dart';
import '../security/device_credentials.dart';

/// Upload connections that are decrypted off the main isolate (D-071).
///
/// dart:io moves TLS data in 8 KB steps, each a round trip through the
/// isolate's event loop. One isolate therefore tops out well below a good
/// Wi-Fi link, and the main isolate also draws the UI. Each lane is an
/// isolate with its own HTTPS listener (same certificate, so the same pin)
/// that takes only `PUT`. It hands the request to the handler on the main
/// isolate, which runs every check and writes the file exactly as for the
/// main port, and forwards the body in pieces of about [piece] bytes.
///
/// A lane forwards nothing before the handler listens to the body, and at
/// most [window] bytes the handler has not taken yet, so a refused request
/// costs no memory and a slow disk slows the sender (hard rule 1).
class DataLanes {
  DataLanes._(this._handler);

  /// Bytes joined into one message to the main isolate.
  static const int piece = 256 * 1024;

  /// Bytes a lane may send ahead of the handler, per upload.
  static const int window = 2 * 1024 * 1024;

  final Handler _handler;
  final List<_Link> _links = [];

  List<int> get ports => [for (final l in _links) l.port];

  /// Starts [count] lanes on [address] (an [InternetAddress] or its text;
  /// every IPv4 address by default), each on a port the system picks.
  static Future<DataLanes> start({
    required DeviceCredentials credentials,
    required Handler handler,
    required int count,
    Object? address,
    int maxHeaderBytes = 16 * 1024,
  }) async {
    final lanes = DataLanes._(handler);
    try {
      for (var i = 0; i < count; i++) {
        lanes._links.add(
          await lanes._spawn(
            credentials,
            address is InternetAddress ? address.address : address as String?,
            maxHeaderBytes,
          ),
        );
      }
    } catch (_) {
      await lanes.close();
      rethrow;
    }
    return lanes;
  }

  Future<_Link> _spawn(
    DeviceCredentials credentials,
    String? address,
    int maxHeaderBytes,
  ) async {
    final fromLane = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      _laneMain,
      [
        fromLane.sendPort,
        credentials.certificatePem,
        credentials.privateKeyPem,
        address,
        maxHeaderBytes,
      ],
      debugName: 'data-lane',
      // One bad connection must not take the lane down.
      errorsAreFatal: false,
      onExit: exit.sendPort,
    );
    final messages = StreamIterator<Object?>(fromLane);
    final exited = exit.first.then<void>((_) => exit.close());
    if (!await messages.moveNext().timeout(const Duration(seconds: 10))) {
      throw const SocketException('data lane did not start');
    }
    final first = messages.current! as List<Object?>;
    if (first[0] != 'port') {
      await messages.cancel();
      throw SocketException('data lane: ${first[1]}');
    }
    final link = _Link(
      isolate,
      first[2]! as SendPort,
      first[1]! as int,
      messages,
      exited,
    );
    unawaited(_pump(link));
    return link;
  }

  Future<void> _pump(_Link l) async {
    while (await l.messages.moveNext()) {
      final msg = l.messages.current! as List<Object?>;
      final id = msg[1]! as int;
      switch (msg[0]) {
        case 'req':
          unawaited(_serve(l, id, msg));
        case 'data':
          final body = l.bodies[id];
          if (body != null && !body.isClosed) {
            body.add(
              (msg[2]! as TransferableTypedData).materialize().asUint8List(),
            );
          }
        case 'end':
          unawaited(l.bodies.remove(id)?.close());
        case 'err':
          _fail(l.bodies.remove(id));
      }
    }
  }

  /// The client went away: every byte it sent has been delivered.
  static void _fail(StreamController<List<int>>? body) {
    if (body == null || body.isClosed) return;
    body.addError(const SocketException('upload connection lost'));
    unawaited(body.close());
  }

  Future<void> _serve(_Link l, int id, List<Object?> msg) async {
    final body = StreamController<List<int>>(
      onListen: () => l.toLane.send(['go', id]),
      onCancel: () => l.toLane.send(['cancel', id]),
    );
    l.bodies[id] = body;
    Response res;
    try {
      res = await _handler(
        Request(
          msg[2]! as String,
          Uri.parse('https://lane${msg[3]}'),
          headers: (msg[4]! as Map).cast<String, String>(),
          // The lane sends more only as the handler takes what it has.
          body: body.stream.map((chunk) {
            l.toLane.send(['ack', id, chunk.length]);
            return chunk;
          }),
          context: {
            'shelf.io.connection_info': _PeerInfo(
              InternetAddress(msg[5]! as String),
              msg[6]! as int,
              l.port,
            ),
          },
        ),
      );
    } catch (e) {
      logEvent('lanes', 'request failed: ${e.runtimeType}');
      res = Response(
        500,
        body: jsonEncode({
          'error': ErrorCodes.ioError,
          'message': 'internal error',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    final bytes = BytesBuilder(copy: false);
    await res.read().forEach(bytes.add);
    l.toLane.send([
      'res',
      id,
      res.statusCode,
      res.headers['content-type'] ?? 'application/json',
      bytes.takeBytes(),
    ]);
    final left = l.bodies.remove(id);
    if (left != null && !left.isClosed) unawaited(left.close());
  }

  /// Stops the lanes; uploads still running see their connection lost.
  Future<void> close() async {
    for (final l in _links) {
      l.toLane.send(const ['close', 0]);
      for (final body in l.bodies.values.toList()) {
        _fail(body);
      }
      l.bodies.clear();
      await l.exited.timeout(
        const Duration(seconds: 2),
        onTimeout: () => l.isolate.kill(priority: Isolate.immediate),
      );
      await l.messages.cancel();
    }
    _links.clear();
  }
}

class _Link {
  _Link(this.isolate, this.toLane, this.port, this.messages, this.exited);

  final Isolate isolate;
  final SendPort toLane;
  final int port;
  final StreamIterator<Object?> messages;
  final Future<void> exited;

  /// Request bodies on their way to the handler, by request id.
  final Map<int, StreamController<List<int>>> bodies = {};
}

/// What the server's address checks read (shelf_io's connection info).
class _PeerInfo implements HttpConnectionInfo {
  _PeerInfo(this.remoteAddress, this.remotePort, this.localPort);

  @override
  final InternetAddress remoteAddress;
  @override
  final int remotePort;
  @override
  final int localPort;
}

// ------------------------------------------------------------ the lane

Future<void> _laneMain(List<Object?> args) async {
  final toMain = args[0]! as SendPort;
  final HttpServer server;
  try {
    final address = args[3] as String?;
    server = await HttpServer.bindSecure(
      address == null ? InternetAddress.anyIPv4 : InternetAddress(address),
      0,
      DeviceCredentials.serverContextFor(
        args[1]! as String,
        args[2]! as String,
      ),
    );
  } catch (e) {
    toMain.send(['fail', e.runtimeType.toString()]);
    return;
  }
  server.idleTimeout = const Duration(seconds: 30);
  final maxHeaderBytes = args[4]! as int;
  final inbox = ReceivePort();
  final calls = <int, _Call>{};
  var next = 0;

  inbox.listen((m) {
    final msg = m as List<Object?>;
    if (msg[0] == 'close') {
      inbox.close();
      unawaited(server.close(force: true));
      return;
    }
    final call = calls[msg[1]];
    if (call == null) return;
    switch (msg[0]) {
      case 'go':
        call.start();
      case 'ack':
        call.acked(msg[2]! as int);
      case 'cancel':
        call.stop();
      case 'res':
        calls.remove(msg[1]);
        call.respond(msg[2]! as int, msg[3]! as String, msg[4]! as Uint8List);
    }
  });

  server.listen((req) {
    final peer = req.connectionInfo;
    final path = req.uri.path;
    if (req.method != 'PUT' || !path.startsWith('/') || peer == null) {
      return _refuse(req, 404, ErrorCodes.notFound, 'unknown route');
    }
    var total = 0;
    final headers = <String, String>{};
    req.headers.forEach((name, values) {
      total += name.length;
      for (final v in values) {
        total += v.length;
      }
      headers[name] = values.join(',');
    });
    if (total > maxHeaderBytes) {
      return _refuse(req, 431, ErrorCodes.headersTooLarge, 'headers too large');
    }
    final id = next++;
    calls[id] = _Call(id, req, toMain);
    toMain.send([
      'req',
      id,
      req.method,
      req.uri.hasQuery ? '$path?${req.uri.query}' : path,
      headers,
      peer.remoteAddress.address,
      peer.remotePort,
    ]);
  }, onError: (Object _) {}); // failed handshakes
  toMain.send(['port', server.port, inbox.sendPort]);
}

void _refuse(HttpRequest req, int status, String code, String message) {
  final body = utf8.encode(jsonEncode({'error': code, 'message': message}));
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..contentLength = body.length
    ..add(body);
  req.response.close().ignore();
}

/// One upload inside a lane: reads the body when the main isolate asks
/// for it and writes the reply.
class _Call {
  _Call(this.id, this.req, this.toMain);

  final int id;
  final HttpRequest req;
  final SendPort toMain;

  StreamSubscription<Uint8List>? _sub;
  List<Uint8List> _parts = [];
  int _partBytes = 0;
  int _unacked = 0;
  Timer? _timer;
  bool _stopped = false;

  void start() {
    if (_sub != null || _stopped) return;
    _sub = req.listen(
      _onData,
      onError: (Object _) {
        _flush();
        toMain.send(['err', id]);
      },
      onDone: () {
        _flush();
        toMain.send(['end', id]);
      },
      cancelOnError: true,
    );
  }

  void _onData(Uint8List chunk) {
    _parts.add(chunk);
    _partBytes += chunk.length;
    if (_partBytes >= DataLanes.piece) {
      _flush();
    } else {
      // A slow link still reaches the handler's idle timeout in time.
      _timer ??= Timer(const Duration(milliseconds: 50), _flush);
    }
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    if (_partBytes == 0) return;
    toMain.send(['data', id, TransferableTypedData.fromList(_parts)]);
    _unacked += _partBytes;
    _parts = [];
    _partBytes = 0;
    final sub = _sub;
    if (_unacked >= DataLanes.window && sub != null && !sub.isPaused) {
      sub.pause();
    }
  }

  void acked(int bytes) {
    _unacked -= bytes;
    final sub = _sub;
    if (sub != null && sub.isPaused && _unacked < DataLanes.window) {
      sub.resume();
    }
  }

  /// The handler stopped reading: read no more from the client.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void respond(int status, String contentType, Uint8List body) {
    stop();
    req.response
      ..statusCode = status
      ..headers.set('content-type', contentType)
      ..contentLength = body.length
      ..add(body);
    // The client may be gone already.
    req.response.close().ignore();
  }
}
