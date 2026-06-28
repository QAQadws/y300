import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

/// Reader-facing persistence boundary for comic reading state.
///
/// The reader should describe what happened in reading terms: progress was
/// saved or an episode was completed.  This writer owns the fan-out to comic
/// progress and unified library state so controller code remains focused.
abstract class ComicReadingStateWriter {
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  });

  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  });

  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  });

  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  });

  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  });

  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  });
}

class DefaultComicReadingStateWriter implements ComicReadingStateWriter {
  const DefaultComicReadingStateWriter({
    required ComicRepository comicRepository,
    required LibraryStateRepository libraryStateRepository,
  })  : _comicRepository = comicRepository,
        _libraryStateRepository = libraryStateRepository;

  final ComicRepository _comicRepository;
  final LibraryStateRepository _libraryStateRepository;

  @override
  Future<bool> isEpisodeRead({
    required String comicId,
    required String episodeId,
  }) async {
    final state = await _libraryStateRepository.getEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
    );
    return state?.isRead ?? false;
  }

  @override
  Future<bool> isEpisodeBookmarked({
    required String comicId,
    required String episodeId,
  }) async {
    final state = await _libraryStateRepository.getEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
    );
    return state?.isBookmarked ?? false;
  }

  @override
  Future<void> saveProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) {
    return _comicRepository.updateLastReadProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
    );
  }

  @override
  Future<void> setEpisodeRead({
    required String comicId,
    required String episodeId,
    required bool isRead,
    DateTime? readAt,
  }) async {
    final effectiveReadAt = isRead ? (readAt ?? DateTime.now()) : null;
    await _libraryStateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: comicId,
      isRead: isRead,
      readAt: effectiveReadAt,
    );
    if (!isRead) {
      return;
    }
    await _libraryStateRepository.upsertWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: comicId,
      lastReadEpisodeId: episodeId,
      lastReadAt: effectiveReadAt,
    );
  }

  @override
  Future<void> setEpisodeBookmarked({
    required String comicId,
    required String episodeId,
    required bool isBookmarked,
  }) {
    return _libraryStateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: comicId,
      isBookmarked: isBookmarked,
    );
  }

  @override
  Future<void> markEpisodeCompleted({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
    required DateTime completedAt,
  }) async {
    await saveProgress(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      scrollOffset: scrollOffset,
    );
    await setEpisodeRead(
      comicId: comicId,
      episodeId: episodeId,
      isRead: true,
      readAt: completedAt,
    );
  }
}
