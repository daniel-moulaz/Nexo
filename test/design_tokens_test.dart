// The design system's rules, kept by the build. See docs/design-system.md.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/theme/app_theme.dart';
import 'package:nexo/widgets/nexo_brand.dart';
import 'package:nexo/widgets/nexo_ui.dart';

double _contrast(Color a, Color b) {
  final hi = math.max(a.computeLuminance(), b.computeLuminance());
  final lo = math.min(a.computeLuminance(), b.computeLuminance());
  return (hi + .05) / (lo + .05);
}

/// Colors written straight in screens and widgets. It may only go down: new
/// code reads the tokens. What is left is mostly each account's own card.
const _literalColorsAllowed = 49;

void main() {
  for (final dark in [true, false]) {
    final name = dark ? 'dark' : 'light';
    final cs = buildTheme(seed: 'nexo', dark: dark).colorScheme;
    final surfaces = {
      'surface': cs.surface,
      'card': cs.surfaceContainerLow,
      'raised': cs.surfaceContainerHigh,
    };

    test('$name: text reads on every surface', () {
      for (final e in surfaces.entries) {
        expect(_contrast(cs.onSurface, e.value), greaterThanOrEqualTo(4.5),
            reason: 'onSurface on ${e.key}');
        expect(
            _contrast(cs.onSurfaceVariant, e.value), greaterThanOrEqualTo(4.5),
            reason: 'onSurfaceVariant on ${e.key}');
      }
      expect(_contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
      expect(_contrast(cs.onPrimaryContainer, cs.primaryContainer),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(cs.primary, cs.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(cs.outline, cs.surface), greaterThanOrEqualTo(3));
    });

    testWidgets('$name: money tones read on every surface', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(seed: 'nexo', dark: dark),
          home: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          })));
      final tones = {
        'income': NexoTones.income(context),
        'expense': NexoTones.expense(context),
        'warning': NexoTones.warning(context),
        'info': NexoTones.info(context),
      };
      for (final tone in tones.entries) {
        for (final surface in surfaces.entries) {
          expect(
              _contrast(tone.value, surface.value), greaterThanOrEqualTo(4.5),
              reason: '${tone.key} on ${surface.key}');
        }
      }
      // A gain can never be taken for the brand.
      final brand = HSLColor.fromColor(cs.primary).hue;
      final gain = HSLColor.fromColor(tones['income']!).hue;
      expect((brand - gain).abs(), greaterThan(60));
    });

    testWidgets('$name: category colors stay readable', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(seed: 'nexo', dark: dark),
          home: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          })));
      for (final stored in const [
        Color(0xFF1B5E20),
        Color(0xFF4A148C),
        Color(0xFFF9A825),
        Color(0xFF37474F),
        Color(0xFFFFFFFF),
      ]) {
        final tone = NexoTones.category(context, stored);
        final fill = Color.alphaBlend(
            tone.withValues(alpha: .16), cs.surfaceContainerLow);
        expect(_contrast(tone, fill), greaterThanOrEqualTo(3),
            reason: '$stored');
      }
    });
  }

  test('the ink panel holds in both themes', () {
    for (final fill in [NexoBrand.ink, NexoBrand.inkHigh]) {
      expect(_contrast(NexoBrand.onInk, fill), greaterThanOrEqualTo(4.5));
      expect(_contrast(NexoBrand.onInkMuted, fill), greaterThanOrEqualTo(4.5));
      expect(_contrast(NexoTones.incomeOnInk, fill), greaterThanOrEqualTo(4.5));
      expect(
          _contrast(NexoTones.expenseOnInk, fill), greaterThanOrEqualTo(4.5));
    }
  });

  test('a fill always gets readable text', () {
    for (final fill in const [
      NexoBrand.teal,
      NexoBrand.tealDeep,
      NexoBrand.ink,
      Color(0xFFF9A825),
    ]) {
      expect(_contrast(NexoTones.on(fill), fill), greaterThanOrEqualTo(4.5));
    }
  });

  test('no new color is written straight in a screen', () {
    final literal = RegExp(r'\bColor\(0x|\bColors\.(?!transparent)[a-zA-Z]+');
    var count = 0;
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        if (f.path.endsWith('nexo_brand.dart')) continue;
        count += literal.allMatches(f.readAsStringSync()).length;
      }
    }
    expect(count, lessThanOrEqualTo(_literalColorsAllowed),
        reason: 'Use lib/theme/nexo_tokens.dart.');
  });

  Widget stage(bool dark, Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed: 'nexo', dark: dark),
      home: Scaffold(
          body: Center(
              child:
                  SizedBox(width: 320, child: RepaintBoundary(child: child)))));

  for (final dark in [true, false]) {
    final name = dark ? 'escuro' : 'claro';
    testWidgets('components, $name', (tester) async {
      tester.view.physicalSize = const Size(400, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(stage(
          dark,
          const Column(mainAxisSize: MainAxisSize.min, children: [
            NexoMark(size: 48),
            SizedBox(height: 12),
            NexoInkPanel(
                child: Row(children: [
              Expanded(child: NexoInkStat(label: 'Entradas', value: '10')),
              Expanded(child: NexoInkStat(label: 'Saídas', value: '5')),
            ])),
            SizedBox(height: 12),
            NexoCard(child: NexoProgress(value: .5)),
            SizedBox(height: 12),
            NexoProgress(value: .9),
            SizedBox(height: 12),
            NexoProgress(value: 1.2),
          ])));
      await tester.pumpAndSettle();
      await expectLater(find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/componentes-$name.png'));
    });
  }
}
