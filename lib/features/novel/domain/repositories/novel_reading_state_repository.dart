import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import '../models/novel_reading_progress.dart';

class NovelReadingStateSnapshot {
  NovelReadingStateSnapshot({
    required this.novelId,
    required Map<String, NovelReadingProgress> progressByEpisode,
    required Map<String, LibraryEpisodeState> episodeStates,
    this.recentEpisodeId,
  }) : progressByEpisode = Map.unmodifiable(progressByEpisode),
       episodeStates = Map.unmodifiable(episodeStates);

  final String novelId;
  final Map<String, NovelReadingProgress> progressByEpisode;
  final Map<String, LibraryEpisodeState> episodeStates;
  final String? recentEpisodeId;
  NovelReadingProgress? get recentProgress =>
      progressByEpisode[recentEpisodeId];
}

/// One atomic boundary for chapter positions, recent chapter and completion.
/// A producer guard is checked inside the transaction, including before commit.
abstract interface class NovelReadingStateRepository {
  Future<NovelReadingStateSnapshot> loadWorkState({required String novelId});
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  });
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  });
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  });
  Future<bool> resetChapter({
    required String novelId,
    required String episodeId,
    bool Function()? canCommit,
  });
}
