import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_font_size_policy_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
  wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
);
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'font-size strategy distinguishes author, body and all ($locale)',
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
                    NovelReaderFontSizePolicySettingsPanel(
                      value: value,
                      enabled: true,
                      onChanged: (next) => update(() => value = next),
                    ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderFontSizePolicySettingsPanel)),
        );
        await tester.tap(find.text(l10n.novelFontSizePolicyBody));
        await tester.pump();
        expect(value.fontSizeScope, NovelReaderStyleScope.forceBody);
        await tester.tap(find.text(l10n.novelFontSizePolicyAll));
        await tester.pump();
        expect(value.fontSizeScope, NovelReaderStyleScope.forceAll);
        expect(find.text(l10n.novelFontSizePolicyAllHint), findsOneWidget);
        await tester.tap(find.text(l10n.novelFontSizePolicyAuthor));
        await tester.pump();
        expect(value.fontSizeScope, NovelReaderStyleScope.asDefault);
        expect(value, isNot(_other));
        await tester.tap(find.byKey(const Key('novel-reader-font-size-reset')));
        await tester.pump();
        expect(value, _other);
      },
    );
  }
  testWidgets('sheet reset retains the chosen size and other requests', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var changed = NovelReaderPreferences.defaults().copyWith(
      fontSize: 20,
      typography: _other,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NovelReaderDisplaySettingsSheet(
              initialPreferences: changed,
              nativeTypography: true,
              onPreferencesChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );
    tester
        .widget<Slider>(
          find.descendant(
            of: find.byKey(const Key('novel-reader-font-size-slider')),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(22);
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelReaderFontSizePolicySettingsPanel)),
    );
    final body = find.descendant(
      of: find.byKey(const Key('novel-reader-font-size-policy')),
      matching: find.text(l10n.novelFontSizePolicyBody),
    );
    await tester.ensureVisible(body);
    await tester.tap(body);
    await tester.pump();
    expect(changed.fontSize, 22);
    expect(changed.typography.fontSizeScope, NovelReaderStyleScope.forceBody);
    final reset = find.byKey(const Key('novel-reader-font-size-reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(changed.fontSize, 22);
    expect(changed.typography, _other);
  });
  testWidgets('unsupported mode retains the strategy and permits only reset', (
    tester,
  ) async {
    var value = _other.withFontSizeScope(NovelReaderStyleScope.forceBody);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) =>
                NovelReaderFontSizePolicySettingsPanel(
                  value: value,
                  enabled: false,
                  onChanged: (next) => update(() => value = next),
                ),
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelReaderFontSizePolicySettingsPanel)),
    );
    expect(find.text(l10n.novelFontSizePolicyUnavailable), findsOneWidget);
    await tester.tap(find.text(l10n.novelFontSizePolicyAll));
    await tester.pump();
    expect(value.fontSizeScope, NovelReaderStyleScope.forceBody);
    await tester.tap(find.byKey(const Key('novel-reader-font-size-reset')));
    await tester.pump();
    expect(value, _other);
  });
}
