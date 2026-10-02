import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_chapter_interactions_dock_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'defaults to a visible right-side button without modifying reader layout',
    () async {
      final repository =
          SharedPreferencesNovelChapterInteractionsDockRepository(
            SharedPreferencesStore(),
          );
      final value = await repository.load();
      expect(value.enabled, isTrue);
      expect(value.side, ReaderCornerDockSide.right);
      final storage = await SharedPreferences.getInstance();
      expect(
        storage.containsKey(PreferenceKeys.novelReaderSnapshotV1.name),
        isFalse,
      );
    },
  );

  test(
    'persists visibility and side separately from thread and reader settings',
    () async {
      final repository =
          SharedPreferencesNovelChapterInteractionsDockRepository(
            SharedPreferencesStore(),
          );
      await repository.save(
        const NovelChapterInteractionsDockPreferences(
          enabled: false,
          side: ReaderCornerDockSide.left,
        ),
      );
      final reloaded =
          await SharedPreferencesNovelChapterInteractionsDockRepository(
            SharedPreferencesStore(),
          ).load();
      expect(reloaded.enabled, isFalse);
      expect(reloaded.side, ReaderCornerDockSide.left);
      final storage = await SharedPreferences.getInstance();
      expect(
        storage.containsKey(PreferenceKeys.novelReaderSnapshotV1.name),
        isFalse,
      );
      expect(
        storage.containsKey(PreferenceKeys.threadQuickScrollDockSide.name),
        isFalse,
      );
    },
  );

  test('invalid or future snapshot falls back to enabled right side', () async {
    final storage = await SharedPreferences.getInstance();
    final repository = SharedPreferencesNovelChapterInteractionsDockRepository(
      SharedPreferencesStore(),
    );
    await storage.setString(
      PreferenceKeys.novelChapterInteractionsDockV1.name,
      jsonEncode(<String, Object>{
        'schemaVersion': 2,
        'enabled': false,
        'side': 'left',
      }),
    );
    expect((await repository.load()).enabled, isTrue);
    await storage.setString(
      PreferenceKeys.novelChapterInteractionsDockV1.name,
      '{invalid',
    );
    expect((await repository.load()).side, ReaderCornerDockSide.right);
  });
}
