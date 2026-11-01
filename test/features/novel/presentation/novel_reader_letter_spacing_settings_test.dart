import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_letter_spacing_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
);
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'localized letter spacing preserves zero, negative and other fields ($locale)',
      (tester) async {
        var value = _other;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) =>
                    NovelReaderLetterSpacingSettingsPanel(
                      value: value,
                      enabled: true,
                      onChanged: (next) => update(() => value = next),
                    ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderLetterSpacingSettingsPanel)),
        );
        expect(find.byType(Slider), findsNothing);
        await tester.tap(find.text(l10n.novelLetterSpacingBody));
        await tester.pump();
        expect(
          value.letterSpacing,
          const NovelReaderLetterSpacing(logicalPixels: 0),
        );
        tester.widget<Slider>(find.byType(Slider)).onChanged!(-1.25);
        await tester.pump();
        expect(value.letterSpacing!.logicalPixels, -1.25);
        expect(
          find.text(l10n.novelLetterSpacingValue('-1.25')),
          findsOneWidget,
        );
        await tester.tap(find.text(l10n.novelLetterSpacingAll));
        await tester.pump();
        expect(
          value.letterSpacing,
          const NovelReaderLetterSpacing(
            logicalPixels: -1.25,
            scope: NovelReaderStyleScope.forceAll,
          ),
        );
        await tester.tap(
          find.byKey(const Key('novel-reader-letter-spacing-reset')),
        );
        await tester.pump();
        expect(value, _other);
      },
    );
  }
  testWidgets(
    'unsupported mode keeps value and disables editing with local reset',
    (tester) async {
      var value = _other.withLetterSpacing(
        const NovelReaderLetterSpacing(logicalPixels: -1.25),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) =>
                  NovelReaderLetterSpacingSettingsPanel(
                    value: value,
                    enabled: false,
                    onChanged: (next) => update(() => value = next),
                  ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderLetterSpacingSettingsPanel)),
      );
      expect(find.text(l10n.novelLetterSpacingUnavailable), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text(l10n.novelLetterSpacingAll));
      await tester.pump();
      expect(value.letterSpacing!.scope, NovelReaderStyleScope.forceBody);
      await tester.tap(
        find.byKey(const Key('novel-reader-letter-spacing-reset')),
      );
      await tester.pump();
      expect(value, _other);
    },
  );
}
