import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/font_licenses.dart';

void main() {
  registerFontLicenses();
  runApp(const ProviderScope(child: CrossDropApp()));
}
