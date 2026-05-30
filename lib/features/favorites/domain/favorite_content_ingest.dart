import 'package:y300/features/favorites/domain/favorite_detail_context.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

abstract class LibraryPostIngestTask {
  const LibraryPostIngestTask();
}

class FavoriteIngestOptions {
  const FavoriteIngestOptions({
    this.mergeIngestedComic = true,
    this.forceComicSearchOnCatalogMiss = false,
  });

  final bool mergeIngestedComic;
  final bool forceComicSearchOnCatalogMiss;
}

class FavoriteContentIngestRequest {
  const FavoriteContentIngestRequest({
    required this.context,
    required this.options,
  });

  final FavoriteDetailContext context;
  final FavoriteIngestOptions options;
}

class FavoriteContentIngestResult {
  const FavoriteContentIngestResult({
    required this.kind,
    required this.workId,
    this.postTasks = const <LibraryPostIngestTask>[],
  });

  final ThreadContentKind kind;
  final String workId;
  final List<LibraryPostIngestTask> postTasks;
}

abstract class FavoriteContentIngestHandler {
  ThreadContentKind get kind;

  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  );

  Future<void> removeFromShelf({required String workId});
}

abstract class FavoriteContentIngestRegistry {
  FavoriteContentIngestHandler handlerFor(ThreadContentKind kind);
}
