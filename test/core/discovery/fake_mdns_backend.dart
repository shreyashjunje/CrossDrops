import 'dart:async';

import 'package:crossdrop/core/discovery/mdns_backend.dart';

/// In-memory [MdnsBackend] for tests.
class FakeMdnsBackend implements MdnsBackend {
  StreamController<MdnsEvent>? _events;
  final List<MdnsAdvertisement?> advertisements = [];
  int browseStarts = 0;
  int browseStops = 0;
  bool failNextBrowse = false;

  bool get isBrowsing => _events != null;
  MdnsAdvertisement? get current =>
      advertisements.isEmpty ? null : advertisements.last;

  void emit(MdnsEvent e) => _events!.add(e);

  @override
  Future<Stream<MdnsEvent>> startBrowsing() async {
    if (failNextBrowse) {
      failNextBrowse = false;
      throw StateError('browse failed');
    }
    browseStarts++;
    _events = StreamController<MdnsEvent>();
    return _events!.stream;
  }

  @override
  Future<void> stopBrowsing() async {
    browseStops++;
    await _events?.close();
    _events = null;
  }

  @override
  Future<void> startAdvertising(MdnsAdvertisement ad) async =>
      advertisements.add(ad);

  @override
  Future<void> stopAdvertising() async => advertisements.add(null);
}
