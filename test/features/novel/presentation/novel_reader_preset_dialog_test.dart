import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preset_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preset_repository.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_preset_dialog.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  testWidgets('save, rename, reset and apply a preset through its controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = SharedPreferencesNovelReaderPresetRepository(
      SharedPreferencesStore(),
    );
    final draft = NovelReaderPreferences.defaults().copyWith(fontSize: 25);
    NovelReaderPresetApplication? applied;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                applied = await showDialog<NovelReaderPresetApplication>(
                  context: context,
                  builder: (_) => NovelReaderPresetDialog(
                    repository: repo,
                    current: draft,
                    fontAvailable: (_) async => true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('novel-reader-presets-dialog'))),
    );
    expect(find.text(l10n.novelReaderPresetsEmpty), findsOneWidget);
    final save = find.byKey(const Key('novel-reader-save-preset'));
    final name = find.byKey(const Key('novel-reader-preset-name'));
    final confirmName = find.byKey(
      const Key('novel-reader-confirm-preset-name'),
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(confirmName).onPressed, isNull);
    await tester.enterText(name, 'Study');
    await tester.pump();
    await tester.tap(confirmName);
    await tester.pumpAndSettle();
    final item = (await repo.load()).single;
    expect(item.preferences, draft);
    final actions = find.byKey(
      ValueKey('novel-reader-preset-actions-${item.id}'),
    );
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.novelReaderRenamePreset));
    await tester.pumpAndSettle();
    await tester.enterText(name, 'Evening');
    await tester.pump();
    await tester.tap(confirmName);
    await tester.pumpAndSettle();
    expect(find.text('Evening'), findsOneWidget);
    expect((await repo.load()).single.id, item.id);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.novelReaderResetPreset));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('novel-reader-confirm-reset-preset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    expect(applied?.preferences, NovelReaderPreferences.defaults());
    expect(applied?.keepCurrentFont, isFalse);
  });
}
