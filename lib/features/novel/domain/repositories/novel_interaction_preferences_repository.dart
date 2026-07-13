import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

abstract interface class NovelInteractionPreferencesRepository {
  Future<NovelChapterOpenMode> loadChapterOpenMode();

  Future<void> saveChapterOpenMode(NovelChapterOpenMode mode);
}
