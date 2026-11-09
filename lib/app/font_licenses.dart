import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled fonts' licences (SIL OFL 1.1) to the list that the
/// About screen's "Open-source licenses" page shows (D-069).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Space Grotesk',
    ], await rootBundle.loadString('assets/fonts/SpaceGrotesk-OFL.txt'));
  });
}
