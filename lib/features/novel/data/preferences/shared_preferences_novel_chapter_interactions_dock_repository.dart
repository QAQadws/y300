import 'dart:convert';

import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';

final class SharedPreferencesNovelChapterInteractionsDockRepository
    implements NovelChapterInteractionsDockPreferencesRepository {
  const SharedPreferencesNovelChapterInteractionsDockRepository(this._store);

  final PreferencesStore _store;

  @override
  Future<NovelChapterInteractionsDockPreferences> load() async {
    final raw = await _store.read(
      PreferenceKeys.novelChapterInteractionsDockV1,
    );
    if (raw == null) return const NovelChapterInteractionsDockPreferences();
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['schemaVersion'] != 1) {
        return const NovelChapterInteractionsDockPreferences();
      }
      return NovelChapterInteractionsDockPreferences(
        enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
        side: data['side'] == ReaderCornerDockSide.left.name
            ? ReaderCornerDockSide.left
            : ReaderCornerDockSide.right,
      );
    } on FormatException {
      return const NovelChapterInteractionsDockPreferences();
    }
  }

  @override
  Future<void> save(NovelChapterInteractionsDockPreferences preferences) =>
      _store.write(
        PreferenceKeys.novelChapterInteractionsDockV1,
        jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'enabled': preferences.enabled,
          'side': preferences.side.name,
        }),
      );
}
