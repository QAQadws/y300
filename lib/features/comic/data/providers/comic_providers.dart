import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart'
    as image_cache;
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/use_cases/comic_shelf_category_assign_use_case_impl.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/domain/services/comic_reader_events.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/thread/data/repositories/thread_reply_page_repository.dart';

final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  return LocalComicRepository(ComicLocalDb.open());
});

final comicDuplicateMergeServiceProvider =
    Provider<ComicDuplicateMergeService?>((ref) {
      final repository = ref.watch(comicRepositoryProvider);
      if (repository is ComicDuplicateMergeRepository) {
        return ComicDuplicateMergeService(
          repository: repository as ComicDuplicateMergeRepository,
        );
      }
      return null;
    });

final comicCoverCacheWriterProvider = Provider<ComicCoverCacheWriter?>((ref) {
  final repository = ref.watch(comicRepositoryProvider);
  return repository is ComicCoverCacheWriter
      ? repository as ComicCoverCacheWriter
      : null;
});

final comicReaderEventLoggerProvider = Provider<ComicReaderEventLogger>((ref) {
  return const ComicReaderEventLogger();
});

final comicReaderFeatureFlagsProvider = Provider<ComicReaderFeatureFlags>((
  ref,
) {
  return ComicReaderFeatureFlags.defaults;
});

final comicCommentLoaderProvider = Provider<ComicCommentLoader>((ref) {
  return DefaultComicCommentLoader(
    repository: ref.watch(threadReplyPageRepositoryProvider),
  );
});

final comicShelfCategoryAssignUseCaseProvider =
    Provider<ShelfCategoryAssignUseCase>((ref) {
      return DefaultComicShelfCategoryAssignUseCase(
        repository: ref.watch(comicRepositoryProvider),
      );
    });

final comicReadingStateWriterProvider = Provider<ComicReadingStateWriter>((
  ref,
) {
  return DefaultComicReadingStateWriter(
    comicRepository: ref.watch(comicRepositoryProvider),
    libraryStateRepository: ref.watch(libraryStateRepositoryProvider),
  );
});

final comicCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  // Compatibility provider kept for older comic code/tests.  The actual stage
  // 04 image cache service now owns cache key policy and metadata persistence.
  return ref.watch(image_cache.imageCacheManagerProvider.future);
});
