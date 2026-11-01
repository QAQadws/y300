import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_color_settings_panel.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';

Finder _key(String key) => find.byKey(Key('novel-reader-$key'));
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'RGB dialog validates/cancels and independent resets preserve requests ($locale)',
      (tester) async {
        var prefs = NovelReaderPreferences.defaults();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => NovelReaderColorSettingsPanel(
                  preferences: prefs,
                  enabled: true,
                  onChanged: (next) =>
                      update(() => prefs = prefs.copyWith(colors: next)),
                ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderColorSettingsPanel)),
        );
        expect(find.text(l10n.novelColorInherited), findsNWidgets(2));
        await tester.tap(_key('foreground-edit'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.novelColorHexHint), findsOneWidget);
        for (final invalid in ['#123', '#GG0000', '#FF112233', '', '-123456']) {
          await tester.enterText(_key('color-input'), invalid);
          await tester.pump();
          expect(find.text(l10n.novelColorHexInvalid), findsOneWidget);
          expect(
            tester.widget<TextButton>(_key('color-apply')).onPressed,
            isNull,
          );
          expect(prefs.colors.isEmpty, true);
        }
        await tester.enterText(_key('color-input'), '  #123aBc  ');
        await tester.pump();
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
        expect(prefs.colors.isEmpty, true);
        Future<void> choose(String part, String value) async {
          await tester.tap(_key('$part-edit'));
          await tester.pumpAndSettle();
          await tester.enterText(_key('color-input'), value);
          await tester.pump();
          await tester.tap(_key('color-apply'));
          await tester.pumpAndSettle();
        }

        await choose('foreground', '#000000');
        expect(prefs.colors.foreground, 0);
        await choose('background', '000000');
        expect(
          prefs.colors,
          const NovelReaderColorOverrides(foreground: 0, background: 0),
        );
        expect(find.text(l10n.novelColorLowContrast), findsOneWidget);
        await choose('background', 'f4EaD7');
        expect(find.text('#F4EAD7'), findsOneWidget);
        expect(find.text(l10n.novelColorHint), findsOneWidget);
        await tester.tap(_key('foreground-reset'));
        await tester.pump();
        expect(
          prefs.colors,
          const NovelReaderColorOverrides(background: 0xf4ead7),
        );
        expect(find.byTooltip(l10n.novelColorForegroundReset), findsOneWidget);
        await tester.tap(_key('background-reset'));
        await tester.pump();
        expect(prefs.colors.isEmpty, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'pending editor uses current preferences and rejects late disabled result',
    (tester) async {
      var prefs = NovelReaderPreferences.defaults();
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, next) {
                update = next;
                return NovelReaderColorSettingsPanel(
                  preferences: prefs,
                  enabled: enabled,
                  onChanged: (colors) =>
                      update(() => prefs = prefs.copyWith(colors: colors)),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(_key('foreground-edit'));
      await tester.pumpAndSettle();
      update(
        () => prefs = prefs.copyWith(
          colors: const NovelReaderColorOverrides(background: 0x123456),
        ),
      );
      await tester.pump();
      await tester.enterText(_key('color-input'), 'abcdef');
      await tester.pump();
      await tester.tap(_key('color-apply'));
      await tester.pumpAndSettle();
      expect(
        prefs.colors,
        const NovelReaderColorOverrides(
          foreground: 0xabcdef,
          background: 0x123456,
        ),
      );
      await tester.tap(_key('foreground-edit'));
      await tester.pumpAndSettle();
      update(() => enabled = false);
      await tester.pump();
      await tester.enterText(_key('color-input'), '000000');
      await tester.pump();
      await tester.tap(_key('color-apply'));
      await tester.pumpAndSettle();
      expect(prefs.colors.foreground, 0xabcdef);
      expect(
        tester.widget<OutlinedButton>(_key('foreground-edit')).onPressed,
        isNull,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderColorSettingsPanel)),
      );
      expect(find.text(l10n.novelColorUnavailable), findsOneWidget);
      await tester.tap(_key('foreground-reset'));
      await tester.pump();
      expect(
        prefs.colors,
        const NovelReaderColorOverrides(background: 0x123456),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy entry hides custom colors and native scrolling preserves disabled controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<void> show(bool native) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: NovelReaderDisplaySettingsSheet(
                key: ValueKey(native),
                nativeTypography: native,
                initialPreferences: NovelReaderPreferences.defaults().copyWith(
                  flowMode: NovelReaderFlowMode.vertical,
                  colors: const NovelReaderColorOverrides(background: 0x123456),
                ),
                onPreferencesChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await show(false);
      await tester.pumpAndSettle();
      expect(find.byType(NovelReaderColorSettingsPanel), findsNothing);
      await show(true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('background-edit'));
      expect(
        tester.widget<OutlinedButton>(_key('background-edit')).onPressed,
        isNull,
      );
      expect(find.text('#123456'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
