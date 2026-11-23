import 'dart:async';
import 'dart:convert';

/// Control messages between the Android bridge and the iPhone's cable
/// link (D-073): one JSON object per line, UTF-8, at most
/// [maxCableLineBytes] with the newline.
const int cableProtocolVersion = 1;

/// Where the iPhone listens for the Android bridge, on 127.0.0.1, tried in
/// this order. Android tries the same list.
const List<int> cableControlPorts = [47913, 47914, 47915];

const int maxCableLineBytes = 4096;

/// Longest device name kept from a hello; longer ones are cut.
const int maxCableNameChars = 100;

sealed class CableMessage {
  const CableMessage();

  Map<String, Object?> toJson();

  /// The line to write, newline included.
  String encode() => '${jsonEncode(toJson())}\n';
}

/// Android → iPhone, first on the control connection and again when its
/// receive port changes. Unauthenticated: used to route and to show a
/// name; the pinned TLS connection proves who answers.
final class CableHello extends CableMessage {
  const CableHello({
    required this.port,
    required this.deviceId,
    required this.name,
    this.version = cableProtocolVersion,
  });

  final int version;

  /// The Android's receive server port.
  final int port;
  final String deviceId;
  final String name;

  @override
  Map<String, Object?> toJson() => {
    't': 'hello',
    'v': version,
    'port': port,
    'id': deviceId,
    'name': name,
  };
}

/// iPhone → Android: connect [port] on the Android to [listen] on the
/// iPhone.
final class CableDial extends CableMessage {
  const CableDial({required this.listen, required this.port});

  final int listen;
  final int port;

  @override
  Map<String, Object?> toJson() => {
    't': 'dial',
    'listen': listen,
    'port': port,
  };
}

/// Android → iPhone: the dial for [listen] could not be made.
final class CableFail extends CableMessage {
  const CableFail({required this.listen});

  final int listen;

  @override
  Map<String, Object?> toJson() => {'t': 'fail', 'listen': listen};
}

bool _isPort(Object? v) => v is int && v > 0 && v < 65536;

/// Parses one line; null for anything invalid or unknown, which the
/// receiver skips.
CableMessage? decodeCableMessage(String line) {
  final Object? m;
  try {
    m = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (m is! Map<String, Object?>) return null;
  switch (m['t']) {
    case 'hello':
      final v = m['v'];
      final port = m['port'];
      final id = m['id'];
      final name = m['name'];
      if (v is! int || !_isPort(port) || id is! String || name is! String) {
        return null;
      }
      if (id.isEmpty || id.length > 64) return null;
      return CableHello(
        version: v,
        port: port! as int,
        deviceId: id,
        name: name.length > maxCableNameChars
            ? name.substring(0, maxCableNameChars)
            : name,
      );
    case 'dial':
      final listen = m['listen'];
      final port = m['port'];
      if (!_isPort(listen) || !_isPort(port)) return null;
      return CableDial(listen: listen! as int, port: port! as int);
    case 'fail':
      final listen = m['listen'];
      if (!_isPort(listen)) return null;
      return CableFail(listen: listen! as int);
  }
  return null;
}

/// Splits [input] into lines at `\n`. A line longer than
/// [maxCableLineBytes] ends the stream with a [FormatException].
Stream<String> cableLines(Stream<List<int>> input) async* {
  final pending = <int>[];
  await for (final chunk in input) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      pending.addAll(chunk.getRange(start, i));
      start = i + 1;
      if (pending.length >= maxCableLineBytes) {
        throw const FormatException('cable line too long');
      }
      yield utf8.decode(pending, allowMalformed: true);
      pending.clear();
    }
    pending.addAll(chunk.getRange(start, chunk.length));
    if (pending.length >= maxCableLineBytes) {
      throw const FormatException('cable line too long');
    }
  }
}
