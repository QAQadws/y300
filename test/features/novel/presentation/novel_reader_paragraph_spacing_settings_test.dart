import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_paragraph_spacing_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'localized spacing controls preserve independent fields ($locale)',
      (tester) async {
        var value = const NovelReaderTypographyOverrides(
          firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) =>
                    NovelReaderParagraphSpacingSettingsPanel(
                      value: value,
                      legacyAfter: 17,
                      enabled: true,
                      onChanged: (next) => update(() => value = next),
                    ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderParagraphSpacingSettingsPanel)),
        );
        expect(find.text(l10n.novelParagraphSpacingOriginal), findsOneWidget);
        expect(find.byType(Slider), findsNothing);
        await tester.tap(find.text(l10n.novelParagraphSpacingBody));
        await tester.pump();
        expect(
          value.paragraphSpacing,
          const NovelReaderParagraphSpacing(before: 0, after: 17),
        );
        Slider slider(String key) => tester.widget<Slider>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Slider),
          ),
        );
        slider('novel-reader-paragraph-before').onChanged!(12);
        await tester.pump();
        slider('novel-reader-paragraph-after').onChanged!(31);
        await tester.pump();
        expect(
          value.paragraphSpacing,
          const NovelReaderParagraphSpacing(before: 12, after: 31),
        );
        await tester.tap(find.text(l10n.novelParagraphSpacingAll));
        await tester.pump();
        expect(
          value.paragraphSpacing,
          const NovelReaderParagraphSpacing(
            before: 12,
            after: 31,
            scope: NovelReaderStyleScope.forceAll,
          ),
        );
        expect(value.firstLineIndent!.em, 1.5);
        await tester.tap(
          find.byKey(const Key('novel-reader-paragraph-spacing-reset')),
        );
        await tester.pump();
        expect(value.paragraphSpacing, isNull);
        expect(value.firstLineIndent!.em, 1.5);
      },
    );
  }
  testWidgets(
    'unsupported mode keeps the request visible and permits only reset',
    (tester) async {
      var value = const NovelReaderTypographyOverrides(
        paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) =>
                  NovelReaderParagraphSpacingSettingsPanel(
                    value: value,
                    legacyAfter: 10,
                    enabled: false,
                    onChanged: (next) => update(() => value = next),
                  ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderParagraphSpacingSettingsPanel)),
      );
      expect(find.text(l10n.novelParagraphSpacingUnavailable), findsOneWidget);
      for (final widget in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(widget.onChanged, isNull);
      }
      await tester.tap(find.text(l10n.novelParagraphSpacingAll));
      await tester.pump();
      expect(value.paragraphSpacing!.scope, NovelReaderStyleScope.forceBody);
      await tester.tap(
        find.byKey(const Key('novel-reader-paragraph-spacing-reset')),
      );
      await tester.pump();
      expect(value.isEmpty, isTrue);
    },
  );
}
