import 'dart:convert';

/// Longest device name in UTF-8 bytes. Fits a DNS label and keeps the TXT
/// record and QR code small.
const int maxDeviceNameBytes = 63;

final RegExp _control = RegExp(
  '[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]',
);
final RegExp _spaces = RegExp(r'\s+');

/// Cleans a device name typed by the user or received from the network:
/// removes control and bidi-override characters, collapses whitespace and
/// cuts it to [maxDeviceNameBytes] without splitting a character.
///
/// Returns an empty string if nothing is left.
String sanitizeDeviceName(String raw) {
  final cleaned = raw.replaceAll(_control, '').replaceAll(_spaces, ' ').trim();
  if (utf8.encode(cleaned).length <= maxDeviceNameBytes) return cleaned;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in cleaned.runes) {
    final ch = String.fromCharCode(rune);
    final len = utf8.encode(ch).length;
    if (bytes + len > maxDeviceNameBytes) break;
    out.write(ch);
    bytes += len;
  }
  return out.toString().trim();
}
