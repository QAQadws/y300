import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_viewport_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _selected = NovelReaderViewportOverrides(
  left: 0,
  top: 12,
  right: 31,
  bottom: 48,
  contentWidth: NovelReaderContentWidth.limited(640),
);
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'four edges, remembered width and independent resets ($locale)',
      (tester) async {
        var value = const NovelReaderViewportOverrides();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, update) =>
                      NovelReaderViewportSettingsPanel(
                        value: value,
                        legacyPadding: 8,
                        legacyMaximumWidth: 720,
                        enabled: true,
                        onChanged: (next) => update(() => value = next),
                      ),
                ),
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NovelReaderViewportSettingsPanel)),
        );
        for (final edge in NovelReaderViewportEdge.values) {
          final toggle = find.byKey(
            Key('novel-reader-viewport-${edge.name}-enabled'),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pump();
          expect(value.marginFor(edge), 8);
          tester
              .widget<Slider>(
                find.byKey(Key('novel-reader-viewport-${edge.name}-slider')),
              )
              .onChanged!(_selected.marginFor(edge)!);
          await tester.pump();
        }
        expect(value, _selected.withContentWidth(null));
        Future<void> widthMode(String label) async {
          final option = find.descendant(
            of: find.byKey(const Key('novel-reader-viewport-width-mode')),
            matching: find.text(label),
          );
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pump();
        }

        await widthMode(l10n.novelViewportWidthLimited);
        final slider = find.byKey(
          const Key('novel-reader-viewport-width-slider'),
        );
        expect(tester.widget<Slider>(slider).value, 720);
        tester.widget<Slider>(slider).onChanged!(640);
        await tester.pump();
        expect(find.text(l10n.novelViewportPixels('640')), findsOneWidget);
        await widthMode(l10n.novelViewportWidthAvailable);
        expect(
          value.contentWidth,
          const NovelReaderContentWidth.available(logicalPixels: 640),
        );
        await widthMode(l10n.novelViewportWidthLimited);
        expect(tester.widget<Slider>(slider).value, 640);
        expect(value, _selected);
        final leftReset = find.byKey(
          const Key('novel-reader-viewport-left-reset'),
        );
        await tester.ensureVisible(leftReset);
        await tester.tap(leftReset);
        await tester.pump();
        expect(value, _selected.withMargin(NovelReaderViewportEdge.left, null));
        final widthReset = find.byKey(
          const Key('novel-reader-viewport-width-reset'),
        );
        await tester.ensureVisible(widthReset);
        await tester.tap(widthReset);
        await tester.pump();
        expect(
          value,
          _selected
              .withMargin(NovelReaderViewportEdge.left, null)
              .withContentWidth(null),
        );
      },
    );
  }
  for (final native in [false, true]) {
    testWidgets(
      'vertical mode retains stored viewport and gates new controls (native=$native)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        var latest = NovelReaderPreferences.defaults().copyWith(
          flowMode: NovelReaderFlowMode.vertical,
          viewport: _selected,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: NovelReaderDisplaySettingsSheet(
                  initialPreferences: latest,
                  nativeTypography: native,
                  onPreferencesChanged: (next) => latest = next,
                ),
              ),
            ),
          ),
        );
        final panel = find.byType(NovelReaderViewportSettingsPanel);
        if (!native) {
          expect(panel, findsNothing);
          return;
        }
        final l10n = AppLocalizations.of(tester.element(panel));
        final toggle = find.byKey(
          const Key('novel-reader-viewport-left-enabled'),
        );
        await tester.ensureVisible(toggle);
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        expect(find.text(l10n.novelViewportUnavailable), findsOneWidget);
        final reset = find.byKey(const Key('novel-reader-viewport-left-reset'));
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pump();
        expect(
          latest.viewport,
          _selected.withMargin(NovelReaderViewportEdge.left, null),
        );
        expect(latest.flowMode, NovelReaderFlowMode.vertical);
      },
    );
  }
}
