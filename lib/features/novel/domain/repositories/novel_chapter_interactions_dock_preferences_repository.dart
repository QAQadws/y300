import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';

abstract interface class NovelChapterInteractionsDockPreferencesRepository {
  Future<NovelChapterInteractionsDockPreferences> load();
  Future<void> save(NovelChapterInteractionsDockPreferences preferences);
}
