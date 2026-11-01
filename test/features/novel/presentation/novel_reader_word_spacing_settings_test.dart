import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_letter_spacing_settings_panel.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_word_spacing_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
);
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('letter and word controls remain independent ($locale)', (
      tester,
    ) async {
      var value = _other;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) {
                  void changed(NovelReaderTypographyOverrides next) =>
                      update(() => value = next);
                  return Column(
                    children: [
                      NovelReaderLetterSpacingSettingsPanel(
                        value: value,
                        enabled: true,
                        onChanged: changed,
                      ),
                      NovelReaderWordSpacingSettingsPanel(
                        value: value,
                        enabled: true,
                        onChanged: changed,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderWordSpacingSettingsPanel)),
      );
      final policy = find.byKey(const Key('novel-reader-word-spacing-policy'));
      final body = find.descendant(
        of: policy,
        matching: find.text(l10n.novelWordSpacingBody),
      );
      await tester.ensureVisible(body);
      await tester.tap(body);
      await tester.pump();
      expect(value.wordSpacing, const NovelReaderWordSpacing(logicalPixels: 0));
      tester
          .widget<Slider>(
            find.byKey(const Key('novel-reader-word-spacing-slider')),
          )
          .onChanged!(7.5);
      await tester.pump();
      expect(value.wordSpacing!.logicalPixels, 7.5);
      expect(find.text(l10n.novelWordSpacingValue('7.50')), findsOneWidget);
      expect(
        tester
            .widget<Slider>(
              find.byKey(const Key('novel-reader-letter-spacing-slider')),
            )
            .value,
        -1.25,
      );
      final all = find.descendant(
        of: policy,
        matching: find.text(l10n.novelWordSpacingAll),
      );
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pump();
      expect(
        value.wordSpacing,
        const NovelReaderWordSpacing(
          logicalPixels: 7.5,
          scope: NovelReaderStyleScope.forceAll,
        ),
      );
      final reset = find.byKey(const Key('novel-reader-word-spacing-reset'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pump();
      expect(value, _other);
    });
  }
  testWidgets(
    'unsupported mode retains the request and only allows local reset',
    (tester) async {
      var value = _other.withWordSpacing(
        const NovelReaderWordSpacing(logicalPixels: 7.5),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => NovelReaderWordSpacingSettingsPanel(
                value: value,
                enabled: false,
                onChanged: (next) => update(() => value = next),
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderWordSpacingSettingsPanel)),
      );
      expect(find.text(l10n.novelWordSpacingUnavailable), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text(l10n.novelWordSpacingAll));
      await tester.pump();
      expect(value.wordSpacing!.scope, NovelReaderStyleScope.forceBody);
      await tester.tap(
        find.byKey(const Key('novel-reader-word-spacing-reset')),
      );
      await tester.pump();
      expect(value, _other);
    },
  );
}
