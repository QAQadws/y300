import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_font_weight_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
  wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
  fontSizeScope: NovelReaderStyleScope.forceBody,
  lineHeightScope: NovelReaderStyleScope.forceAll,
);

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'base weight starts at 400; every scope and reset is independent ($locale)',
      (tester) async {
        var value = _other;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, update) =>
                      NovelReaderFontWeightSettingsPanel(
                        value: value,
                        enabled: true,
                        onChanged: (next) => update(() => value = next),
                      ),
                ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderFontWeightSettingsPanel)),
        );
        Future<void> choose(String label) async {
          final choice = find.descendant(
            of: find.byKey(const Key('novel-reader-font-weight-policy')),
            matching: find.text(label),
          );
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pump();
        }

        await choose(l10n.novelFontWeightBody);
        expect(value.fontWeight, const NovelReaderFontWeight(value: 400));
        final slider = tester.widget<Slider>(
          find.byKey(const Key('novel-reader-font-weight-slider')),
        );
        expect((slider.min, slider.max, slider.divisions), (100.0, 800.0, 7));
        expect(
          slider.semanticFormatterCallback!(700),
          l10n.novelFontWeightValue('700'),
        );
        slider.onChanged!(700);
        await tester.pump();
        await choose(l10n.novelFontWeightAll);
        expect(
          value.fontWeight,
          const NovelReaderFontWeight(
            value: 700,
            scope: NovelReaderStyleScope.forceAll,
          ),
        );
        await choose(l10n.novelFontWeightMissing);
        expect(
          value.fontWeight,
          const NovelReaderFontWeight(
            value: 700,
            scope: NovelReaderStyleScope.asDefault,
          ),
        );
        final reset = find.byKey(const Key('novel-reader-font-weight-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pump();
        expect(value, _other);
        expect(
          find.byKey(const Key('novel-reader-font-weight-slider')),
          findsNothing,
        );
        await choose(l10n.novelFontWeightBody);
        await choose(l10n.novelFontWeightOriginal);
        expect(value, _other);
      },
    );
  }
  testWidgets(
    'unavailable mode retains weight and only allows independent reset',
    (tester) async {
      var value = _other.withFontWeight(
        const NovelReaderFontWeight(value: 800),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) =>
                    NovelReaderFontWeightSettingsPanel(
                      value: value,
                      enabled: false,
                      onChanged: (next) => update(() => value = next),
                    ),
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderFontWeightSettingsPanel)),
      );
      expect(find.text(l10n.novelFontWeightUnavailable), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text(l10n.novelFontWeightAll));
      await tester.pump();
      expect(value.fontWeight!.scope, NovelReaderStyleScope.forceBody);
      final reset = find.byKey(const Key('novel-reader-font-weight-reset'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pump();
      expect(value, _other);
    },
  );
}
