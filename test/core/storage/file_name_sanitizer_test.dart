import 'dart:convert';
import 'dart:io';

import 'package:crossdrop/core/storage/file_name_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('sanitizeFileName', () {
    test('keeps a normal name', () {
      expect(sanitizeFileName('IMG_4021.MOV'), 'IMG_4021.MOV');
      expect(sanitizeFileName('Résumé 2026.pdf'), 'Résumé 2026.pdf');
    });

    test('strips directories', () {
      expect(sanitizeFileName('../../evil.sh'), 'evil.sh');
      expect(sanitizeFileName('/etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\Windows\win.ini'), 'win.ini');
      expect(sanitizeFileName('a/b/'), 'file');
    });

    test('never returns dot names or empty', () {
      for (final bad in ['', '.', '..', '...', '   ', '/', '. .']) {
        final out = sanitizeFileName(bad);
        expect(out, isNotEmpty, reason: bad);
        expect(out, isNot(anyOf('.', '..')), reason: bad);
      }
    });

    test('removes leading dots (hidden files)', () {
      expect(sanitizeFileName('.bashrc'), 'bashrc');
    });

    test('replaces control and reserved characters', () {
      expect(sanitizeFileName('a\u0000b\nc\u007f.txt'), 'a_b_c_.txt');
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
    });

    test('removes bidi and zero-width characters (review L8)', () {
      // RIGHT-TO-LEFT OVERRIDE: shown as "photoexe.jpg", really an .exe.
      expect(sanitizeFileName('photo\u202Egpj.exe'), 'photogpj.exe');
      expect(sanitizeFileName('a\u2066b\u2069c\u200Fd.txt'), 'abcd.txt');
      expect(
        sanitizeFileName('in\u200Bvis\u200Dible\uFEFF.pdf'),
        'invisible.pdf',
      );
      expect(sanitizeFileName('soft\u00ADhyphen.jpg'), 'softhyphen.jpg');
      // Nothing left but invisible characters.
      expect(sanitizeFileName('\u202E\u200B'), 'file');
      // An extension hidden behind them is found again.
      expect(sanitizeFileName('x.\u200Bjpg'), 'x.jpg');
    });

    test('replaces C1 control characters', () {
      expect(sanitizeFileName('a\u0085b\u009Fc.txt'), 'a_b_c.txt');
    });

    test('keeps ordinary non-Latin names', () {
      expect(sanitizeFileName('写真 2026.heic'), '写真 2026.heic');
      expect(sanitizeFileName('صورة.jpg'), 'صورة.jpg');
      expect(sanitizeFileName('😀 party.mov'), '😀 party.mov');
    });

    test('strips trailing dots and spaces', () {
      expect(sanitizeFileName('name.txt. . '), 'name.txt');
    });

    test('renames reserved device names', () {
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('nul.txt'), '_nul.txt');
      expect(sanitizeFileName('com1.jpg'), '_com1.jpg');
      expect(sanitizeFileName('console.txt'), 'console.txt');
    });

    test('limits length and keeps extension', () {
      final out = sanitizeFileName('${'a' * 500}.jpeg');
      expect(utf8.encode(out).length, lessThanOrEqualTo(maxFileNameBytes));
      expect(out, endsWith('.jpeg'));
    });

    test('truncates multibyte names on character boundaries', () {
      final out = sanitizeFileName('${'é' * 300}.png');
      expect(utf8.encode(out).length, lessThanOrEqualTo(maxFileNameBytes));
      expect(out, endsWith('.png'));
      expect(out.runes.where((r) => r == 0xFFFD), isEmpty);
    });
  });

  group('availablePath', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cd_san'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns the name when free', () {
      expect(availablePath(dir.path, 'a.txt'), p.join(dir.path, 'a.txt'));
    });

    test('adds a counter when taken', () {
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('x');
      File(p.join(dir.path, 'a (1).txt')).writeAsStringSync('x');
      expect(availablePath(dir.path, 'a.txt'), p.join(dir.path, 'a (2).txt'));
    });
  });

  group('claimPath', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cd_claim'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('creates the file and skips taken names', () async {
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('x');
      Directory(p.join(dir.path, 'a (1).txt')).createSync();
      final got = await claimPath(dir.path, 'a.txt');
      expect(got, p.join(dir.path, 'a (2).txt'));
      expect(File(got).lengthSync(), 0);
      expect(File(p.join(dir.path, 'a.txt')).readAsStringSync(), 'x');
    });

    test('parallel claims never share a name (review L1)', () async {
      final got = await Future.wait([
        for (var i = 0; i < 20; i++) claimPath(dir.path, 'IMG_1.JPG'),
      ]);
      expect(got.toSet(), hasLength(20));
      expect(got.every((path) => File(path).existsSync()), isTrue);
    });
  });
}
