import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_author_color_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _rgb = NovelReaderColorOverrides(
  foreground: 0x203040,
  background: 0xe8f0d8,
);
Finder _key(String property, String suffix) =>
    find.byKey(Key('novel-reader-author-$property-$suffix'));
Future<void> _choose(WidgetTester tester, String property, String label) async {
  final target = find.descendant(
    of: _key(property, 'policy'),
    matching: find.text(label),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'independent author colors and resets keep RGB values ($locale)',
      (tester) async {
        var colors = _rgb;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, update) =>
                      NovelReaderAuthorColorSettingsPanel(
                        value: colors,
                        enabled: true,
                        onChanged: (next) => update(() => colors = next),
                      ),
                ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderAuthorColorSettingsPanel)),
        );
        await _choose(tester, 'foreground', l10n.novelAuthorForegroundBody);
        expect(
          colors,
          _rgb.withForegroundScope(NovelReaderStyleScope.forceBody),
        );
        await _choose(tester, 'background', l10n.novelAuthorBackgroundAll);
        expect(
          colors,
          _rgb
              .withForegroundScope(NovelReaderStyleScope.forceBody)
              .withBackgroundScope(NovelReaderStyleScope.forceAll),
        );
        expect(find.text(l10n.novelAuthorBackgroundAllHint), findsOneWidget);
        await _choose(tester, 'foreground', l10n.novelAuthorForegroundAll);
        expect(find.text(l10n.novelAuthorForegroundAllHint), findsOneWidget);
        await _choose(tester, 'foreground', l10n.novelAuthorColorPreserve);
        expect(colors.foregroundScope, NovelReaderStyleScope.asDefault);
        await tester.tap(_key('foreground', 'reset'));
        await tester.pump();
        expect(
          colors,
          _rgb.withBackgroundScope(NovelReaderStyleScope.forceAll),
        );
        await _choose(tester, 'background', l10n.novelAuthorBackgroundBody);
        expect(colors.backgroundScope, NovelReaderStyleScope.forceBody);
        await _choose(tester, 'background', l10n.novelAuthorColorOriginal);
        expect(colors, _rgb);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'inactive controls retain and independently reset author policies in a narrow scaled viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var colors = _rgb
          .withForegroundScope(NovelReaderStyleScope.forceBody)
          .withBackgroundScope(NovelReaderStyleScope.forceAll);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) =>
                    NovelReaderAuthorColorSettingsPanel(
                      value: colors,
                      enabled: false,
                      onChanged: (next) => update(() => colors = next),
                    ),
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelReaderAuthorColorSettingsPanel)),
      );
      expect(find.text(l10n.novelAuthorColorUnavailable), findsNWidgets(2));
      await _choose(tester, 'foreground', l10n.novelAuthorForegroundAll);
      expect(colors.foregroundScope, NovelReaderStyleScope.forceBody);
      await tester.ensureVisible(_key('foreground', 'reset'));
      await tester.tap(_key('foreground', 'reset'));
      await tester.pump();
      expect(colors, _rgb.withBackgroundScope(NovelReaderStyleScope.forceAll));
      await tester.ensureVisible(_key('background', 'reset'));
      await tester.tap(_key('background', 'reset'));
      await tester.pump();
      expect(colors, _rgb);
      expect(tester.takeException(), isNull);
    },
  );
}
