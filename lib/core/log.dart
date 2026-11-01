import 'dart:developer' as developer;

/// Logs ids, offsets, sizes and states only: never file contents, file
/// names, certificates, keys or QR payloads (CLAUDE.md hard rule 7).
///
/// Also prints, so lines show up in `adb logcat -s flutter` and
/// `flutter logs` in release builds.
void logEvent(String area, String message) {
  developer.log(message, name: 'crossdrop.$area');
  // ignore: avoid_print
  print('[crossdrop.$area] $message');
}
