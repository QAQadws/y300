import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_indent_settings_panel.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_paragraph_spacing_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'localized scope, em amount, author and reset form one draft $locale',
      (tester) async {
        var value = const NovelReaderTypographyOverrides();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => SingleChildScrollView(
                  child: NovelReaderIndentSettingsPanel(
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
          tester.element(find.byType(NovelReaderIndentSettingsPanel)),
        );
        await tester.tap(find.text(l10n.novelIndentBody));
        await tester.pump();
        expect(value.firstLineIndent!.em, 2);
        final slider = tester.widget<Slider>(
          find.byKey(const Key('novel-reader-indent-slider')),
        );
        slider.onChanged!(1.5);
        await tester.pump();
        expect(value.firstLineIndent!.em, 1.5);
        expect(find.text(l10n.novelIndentEmValue('1.50')), findsOneWidget);
        await tester.tap(find.text(l10n.novelIndentAll));
        await tester.pump();
        expect(value.firstLineIndent!.scope, NovelReaderStyleScope.forceAll);
        expect(value.firstLineIndent!.em, 1.5);
        await tester.tap(find.text(l10n.novelIndentAuthor));
        await tester.pump();
        expect(
          value.firstLineIndent,
          const NovelReaderFirstLineIndent.followAuthor(),
        );
        expect(find.byType(Slider), findsNothing);
        await tester.tap(find.byKey(const Key('novel-reader-indent-reset')));
        await tester.pump();
        expect(value.isEmpty, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unavailable mode displays the request, disables edits and permits reset',
    (tester) async {
      var value = const NovelReaderTypographyOverrides(
        firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => NovelReaderIndentSettingsPanel(
                value: value,
                enabled: false,
                onChanged: (next) => update(() => value = next),
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderIndentSettingsPanel)),
      );
      expect(find.text(l10n.novelIndentUnavailableMode), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      await tester.tap(find.text(l10n.novelIndentAll));
      await tester.pump();
      expect(value.firstLineIndent!.scope, NovelReaderStyleScope.forceBody);
      await tester.tap(find.byKey(const Key('novel-reader-indent-reset')));
      await tester.pump();
      expect(value.isEmpty, isTrue);
    },
  );

  testWidgets(
    'old consumer hides new controls while native paging exposes them',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<void> pump(bool native, NovelReaderFlowMode mode) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: NovelReaderDisplaySettingsSheet(
                  initialPreferences: NovelReaderPreferences.defaults()
                      .copyWith(flowMode: mode),
                  nativeTypography: native,
                  onPreferencesChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(false, NovelReaderFlowMode.pagedLtr);
      expect(find.byType(NovelReaderIndentSettingsPanel), findsNothing);
      expect(
        find.byType(NovelReaderParagraphSpacingSettingsPanel),
        findsNothing,
      );
      await pump(true, NovelReaderFlowMode.pagedLtr);
      expect(find.byType(NovelReaderIndentSettingsPanel), findsOneWidget);
      expect(
        find.byType(NovelReaderParagraphSpacingSettingsPanel),
        findsOneWidget,
      );
      expect(
        tester
            .widget<NovelReaderIndentSettingsPanel>(
              find.byType(NovelReaderIndentSettingsPanel),
            )
            .enabled,
        isTrue,
      );
      await pump(true, NovelReaderFlowMode.vertical);
      expect(
        tester
            .widget<NovelReaderParagraphSpacingSettingsPanel>(
              find.byType(NovelReaderParagraphSpacingSettingsPanel),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<NovelReaderIndentSettingsPanel>(
              find.byType(NovelReaderIndentSettingsPanel),
            )
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
