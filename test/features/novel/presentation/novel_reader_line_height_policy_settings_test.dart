import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_line_height_policy_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
  wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
  fontSizeScope: NovelReaderStyleScope.forceBody,
);
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'line-height strategy distinguishes author, body and all ($locale)',
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
                    NovelReaderLineHeightPolicySettingsPanel(
                      value: value,
                      enabled: true,
                      onChanged: (next) => update(() => value = next),
                    ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderLineHeightPolicySettingsPanel)),
        );
        await tester.tap(find.text(l10n.novelLineHeightPolicyBody));
        await tester.pump();
        expect(value.lineHeightScope, NovelReaderStyleScope.forceBody);
        await tester.tap(find.text(l10n.novelLineHeightPolicyAll));
        await tester.pump();
        expect(value.lineHeightScope, NovelReaderStyleScope.forceAll);
        expect(find.text(l10n.novelLineHeightPolicyAllHint), findsOneWidget);
        await tester.tap(find.text(l10n.novelLineHeightPolicyAuthor));
        await tester.pump();
        expect(value.lineHeightScope, NovelReaderStyleScope.asDefault);
        expect(value, isNot(_other));
        await tester.tap(
          find.byKey(const Key('novel-reader-line-height-reset')),
        );
        await tester.pump();
        expect(value, _other);
      },
    );
  }
  testWidgets('sheet reset retains the chosen line height and other requests', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var changed = NovelReaderPreferences.defaults().copyWith(
      lineHeight: 1.8,
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
            of: find.byKey(const Key('novel-reader-line-height-slider')),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(2.0);
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelReaderLineHeightPolicySettingsPanel)),
    );
    final body = find.descendant(
      of: find.byKey(const Key('novel-reader-line-height-policy')),
      matching: find.text(l10n.novelLineHeightPolicyBody),
    );
    await tester.ensureVisible(body);
    await tester.tap(body);
    await tester.pump();
    expect(changed.lineHeight, 2.0);
    expect(changed.typography.lineHeightScope, NovelReaderStyleScope.forceBody);
    final reset = find.byKey(const Key('novel-reader-line-height-reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(changed.lineHeight, 2.0);
    expect(changed.typography, _other);
  });
  testWidgets('unsupported mode retains the strategy and permits only reset', (
    tester,
  ) async {
    var value = _other.withLineHeightScope(NovelReaderStyleScope.forceBody);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) =>
                NovelReaderLineHeightPolicySettingsPanel(
                  value: value,
                  enabled: false,
                  onChanged: (next) => update(() => value = next),
                ),
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelReaderLineHeightPolicySettingsPanel)),
    );
    expect(find.text(l10n.novelLineHeightPolicyUnavailable), findsOneWidget);
    await tester.tap(find.text(l10n.novelLineHeightPolicyAll));
    await tester.pump();
    expect(value.lineHeightScope, NovelReaderStyleScope.forceBody);
    await tester.tap(find.byKey(const Key('novel-reader-line-height-reset')));
    await tester.pump();
    expect(value, _other);
  });
}
