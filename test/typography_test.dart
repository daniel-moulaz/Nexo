// The app's type rules, kept by the build. They exist because the Windows app
// once read badly for reasons no widget test sees: weights above 700 fell on
// Segoe UI Black, labels went down to 9 px and tracking tuned for Roboto was
// applied to everything.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/theme/app_theme.dart';

Iterable<File> _sources() =>
    Directory('lib').listSync(recursive: true).whereType<File>().where((f) {
      final path = f.path.replaceAll(r'\', '/');
      return path.endsWith('.dart') &&
          !path.contains('/l10n/') &&
          !path.endsWith('theme/app_theme.dart');
    });

ThemeData _theme({String appFont = 'default', bool dark = true}) =>
    buildTheme(seed: 'nexo', dark: dark, appFont: appFont);

void main() {
  test('no weight above 700: the bundled font has none', () {
    final heavy = RegExp(r'FontWeight\.(w800|w900)');
    final found = [
      for (final f in _sources())
        if (heavy.hasMatch(f.readAsStringSync())) f.path
    ];
    expect(found, isEmpty);
  });

  test('no literal text size under 12', () {
    final size = RegExp(r'fontSize:\s*\(?(\d+(?:\.\d+)?)');
    final found = [
      for (final f in _sources())
        for (final m in size.allMatches(f.readAsStringSync()))
          if (double.parse(m[1]!) < 12) '${f.path}: ${m[0]}'
    ];
    expect(found, isEmpty);
  });

  test('tracking stays in the theme', () {
    final found = [
      for (final f in _sources())
        if (f.readAsStringSync().contains('letterSpacing:') &&
            !f.path.endsWith('app_theme.dart'))
          f.path
    ];
    expect(found, isEmpty);
  });

  test('the type ramp: nothing under 12, no tracking', () {
    for (final dark in [false, true]) {
      final t = _theme(dark: dark).textTheme;
      for (final style in [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(style!.fontSize, greaterThanOrEqualTo(12));
        expect(style.letterSpacing, 0);
        expect(style.fontWeight!.value, lessThanOrEqualTo(700));
      }
    }
  });

  test('no theme style has tabular figures: they widen the hyphen in Inter',
      () {
    final t = _theme().textTheme;
    for (final style in [
      t.displayLarge,
      t.displayMedium,
      t.displaySmall,
      t.headlineLarge,
      t.headlineMedium,
      t.headlineSmall,
      t.titleLarge,
      t.titleMedium,
      t.titleSmall,
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.labelLarge,
      t.labelMedium,
      t.labelSmall,
    ]) {
      expect(style!.fontFeatures ?? const [],
          isNot(contains(const FontFeature.tabularFigures())));
    }
  });

  test('Inter ships with the app, with its license, in every used weight', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final (file, weight) in const [
      ('Inter-Regular.ttf', 400),
      ('Inter-Medium.ttf', 500),
      ('Inter-SemiBold.ttf', 600),
      ('Inter-Bold.ttf', 700),
    ]) {
      expect(File('assets/fonts/Inter/$file').existsSync(), isTrue);
      expect(RegExp('$file\\s+weight: $weight').hasMatch(pubspec), isTrue,
          reason: file);
    }
    expect(File('assets/fonts/Inter/OFL.txt').existsSync(), isTrue);
    expect(pubspec, contains('assets/fonts/Inter/OFL.txt'));
  });

  test('choosing Inter never needs the network', () {
    final t = buildTheme(seed: 'sky', dark: true, appFont: 'inter').textTheme;
    expect(t.bodyMedium!.fontFamily, kBundledFont);
  });
}
