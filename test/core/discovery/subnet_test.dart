import 'package:crossdrop/core/discovery/network_monitor.dart';
import 'package:crossdrop/core/discovery/subnet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sameSubnet', () {
    test('/24', () {
      expect(sameSubnet('192.168.1.10', '192.168.1.200', 24), isTrue);
      expect(sameSubnet('192.168.1.10', '192.168.2.10', 24), isFalse);
    });

    test('/28, the iPhone hotspot range', () {
      expect(sameSubnet('172.20.10.1', '172.20.10.14', 28), isTrue);
      expect(sameSubnet('172.20.10.1', '172.20.10.17', 28), isFalse);
    });

    test('/16 and /32 and /0', () {
      expect(sameSubnet('10.1.2.3', '10.1.200.1', 16), isTrue);
      expect(sameSubnet('10.1.2.3', '10.1.2.3', 32), isTrue);
      expect(sameSubnet('10.1.2.3', '10.1.2.4', 32), isFalse);
      expect(sameSubnet('10.1.2.3', '192.168.0.1', 0), isTrue);
    });

    test('rejects bad input', () {
      expect(sameSubnet('x', '10.0.0.1', 24), isFalse);
      expect(sameSubnet('10.0.0.1', '10.0.0.2', 33), isFalse);
      expect(sameSubnet('10.0.0.1', '10.0.0.2', -1), isFalse);
    });
  });

  test('addressSharingSubnet picks the matching interface', () {
    const mine = [
      InterfaceAddress('rmnet0', '10.20.30.40', 30),
      InterfaceAddress('wlan0', '172.20.10.3', 28),
    ];
    expect(addressSharingSubnet(mine, '172.20.10.1')?.name, 'wlan0');
    expect(addressSharingSubnet(mine, '192.168.1.1'), isNull);
    // A /31 or /32 never counts.
    expect(
      addressSharingSubnet(const [
        InterfaceAddress('tun0', '10.0.0.1', 32),
      ], '10.0.0.1'),
      isNull,
    );
  });

  test('looksLikeIphoneHotspot', () {
    expect(looksLikeIphoneHotspot('172.20.10.1'), isTrue);
    expect(looksLikeIphoneHotspot('172.20.10.15'), isTrue);
    expect(looksLikeIphoneHotspot('172.20.10.16'), isFalse);
    expect(looksLikeIphoneHotspot('192.168.43.1'), isFalse);
  });

  group('pickHotspotAddress', () {
    const wifi = LocalAddress('192.168.1.20', 'wlan0');
    const cell = LocalAddress('10.40.0.2', 'rmnet_data0');

    test('a new address on a hotspot interface', () {
      expect(
        pickHotspotAddress(
          [wifi, cell],
          [wifi, cell, const LocalAddress('192.168.49.1', 'swlan0')],
        ),
        const LocalAddress('192.168.49.1', 'swlan0'),
      );
    });

    test('Wi-Fi client dropped, hotspot came up on wlan1', () {
      expect(
        pickHotspotAddress(
          [wifi],
          [const LocalAddress('10.191.82.1', 'wlan1')],
        ),
        const LocalAddress('10.191.82.1', 'wlan1'),
      );
    });

    test('a new address on an unknown interface name', () {
      expect(
        pickHotspotAddress(
          [wifi],
          [wifi, const LocalAddress('192.168.120.1', 'br0')],
        ),
        const LocalAddress('192.168.120.1', 'br0'),
      );
    });

    test('already running (shared with another app)', () {
      const ap = LocalAddress('192.168.49.1', 'ap0');
      expect(pickHotspotAddress([wifi, ap], [wifi, ap]), ap);
    });

    test('never mobile data, and null before the address appears', () {
      expect(
        pickHotspotAddress(
          [wifi],
          [wifi, const LocalAddress('10.40.0.9', 'rmnet_data1')],
        ),
        isNull,
      );
      expect(pickHotspotAddress([wifi], [wifi]), isNull);
    });
  });

  group('shouldBindToWifi', () {
    test('binds only for Wi-Fi without internet that is not the default', () {
      expect(
        shouldBindToWifi(connected: true, validated: false, isDefault: false),
        isTrue,
      );
    });

    test('no binding otherwise', () {
      for (final (c, v, d) in [
        (false, false, false), // No Wi-Fi.
        (true, true, true), // Normal home Wi-Fi.
        (true, true, false), // VPN is the default.
        (true, false, true), // No mobile data: Wi-Fi stays default.
      ]) {
        expect(
          shouldBindToWifi(connected: c, validated: v, isDefault: d),
          isFalse,
          reason: '($c, $v, $d)',
        );
      }
    });
  });
}
