import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_text_alignment_settings_panel.dart';
import 'package:y300/l10n/app_localizations.dart';

const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
  wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
  fontWeight: NovelReaderFontWeight(value: 700),
  fontSizeScope: NovelReaderStyleScope.forceBody,
  lineHeightScope: NovelReaderStyleScope.forceAll,
);

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'alignment mode and scope edit/reset retain other settings ($locale)',
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
                      NovelReaderTextAlignmentSettingsPanel(
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
          tester.element(find.byType(NovelReaderTextAlignmentSettingsPanel)),
        );
        Future<void> choose(String key, String label) async {
          final choice = find.descendant(
            of: find.byKey(Key(key)),
            matching: find.text(label),
          );
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pump();
        }

        const policy = 'novel-reader-text-alignment-policy';
        const modes = 'novel-reader-text-alignment-mode';
        expect(find.byKey(const Key(modes)), findsNothing);
        await choose(policy, l10n.novelTextAlignmentBody);
        expect(
          value.textAlignment,
          const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.start),
        );
        for (final (mode, label) in [
          (NovelReaderTextAlignMode.end, l10n.novelTextAlignmentEnd),
          (NovelReaderTextAlignMode.justify, l10n.novelTextAlignmentJustify),
          (NovelReaderTextAlignMode.center, l10n.novelTextAlignmentCenter),
          (NovelReaderTextAlignMode.start, l10n.novelTextAlignmentStart),
        ]) {
          await choose(modes, label);
          expect(value.textAlignment!.mode, mode);
        }
        await choose(policy, l10n.novelTextAlignmentAll);
        expect(value.textAlignment!.scope, NovelReaderStyleScope.forceAll);
        expect(find.text(l10n.novelTextAlignmentAllHint), findsOneWidget);
        await choose(policy, l10n.novelTextAlignmentMissing);
        expect(value.textAlignment!.scope, NovelReaderStyleScope.asDefault);
        final reset = find.byKey(
          const Key('novel-reader-text-alignment-reset'),
        );
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pump();
        expect(value, _other);
        await choose(policy, l10n.novelTextAlignmentBody);
        await choose(policy, l10n.novelTextAlignmentOriginal);
        expect(value, _other);
      },
    );
  }
  for (final (native, mode) in [
    (false, NovelReaderFlowMode.pagedLtr),
    (true, NovelReaderFlowMode.vertical),
    (true, NovelReaderFlowMode.pagedLtr),
  ]) {
    testWidgets(
      'sheet advertises only supported controls and suppresses equivalent edits ($native, $mode)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final initial = NovelReaderPreferences.defaults().copyWith(
          flowMode: mode,
          typography: _other.withTextAlignment(
            const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.end),
          ),
        );
        final changed = <NovelReaderPreferences>[];
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: NovelReaderDisplaySettingsSheet(
                  initialPreferences: initial,
                  nativeTypography: native,
                  onPreferencesChanged: changed.add,
                ),
              ),
            ),
          ),
        );
        final panel = find.byType(NovelReaderTextAlignmentSettingsPanel);
        if (!native) {
          expect(panel, findsNothing);
          expect(changed, isEmpty);
          return;
        }
        final l10n = AppLocalizations.of(tester.element(panel));
        final center = find.text(l10n.novelTextAlignmentCenter);
        await tester.ensureVisible(center);
        if (mode == NovelReaderFlowMode.vertical) {
          expect(find.text(l10n.novelTextAlignmentUnavailable), findsOneWidget);
          await tester.tap(center);
          await tester.pump();
          expect(changed, isEmpty);
        } else {
          await tester.tap(find.text(l10n.novelTextAlignmentEnd));
          await tester.pump();
          expect(changed, isEmpty);
          await tester.tap(center);
          await tester.pump();
          expect(
            changed.single.typography.textAlignment!.mode,
            NovelReaderTextAlignMode.center,
          );
        }
        final reset = find.byKey(
          const Key('novel-reader-text-alignment-reset'),
        );
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pump();
        expect(changed.last.typography, _other);
        expect(changed.last.flowMode, mode);
      },
    );
  }
}
