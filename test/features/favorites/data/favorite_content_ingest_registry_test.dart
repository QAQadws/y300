import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('returns comic handler for comic kind', () {
    final comicHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.comic,
    );
    final novelHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.novel,
    );
    final forumHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.forum,
    );
    final registry = DefaultFavoriteContentIngestRegistry(
      comicHandler: comicHandler,
      novelHandler: novelHandler,
      forumHandler: forumHandler,
    );

    expect(registry.handlerFor(ThreadContentKind.comic), same(comicHandler));
  });

  test('returns novel handler for novel kind', () {
    final comicHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.comic,
    );
    final novelHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.novel,
    );
    final forumHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.forum,
    );
    final registry = DefaultFavoriteContentIngestRegistry(
      comicHandler: comicHandler,
      novelHandler: novelHandler,
      forumHandler: forumHandler,
    );

    expect(registry.handlerFor(ThreadContentKind.novel), same(novelHandler));
  });

  test('returns forum handler for forum and unknown kinds', () {
    final comicHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.comic,
    );
    final novelHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.novel,
    );
    final forumHandler = _StubFavoriteContentIngestHandler(
      kind: ThreadContentKind.forum,
    );
    final registry = DefaultFavoriteContentIngestRegistry(
      comicHandler: comicHandler,
      novelHandler: novelHandler,
      forumHandler: forumHandler,
    );

    expect(registry.handlerFor(ThreadContentKind.forum), same(forumHandler));
    expect(registry.handlerFor(ThreadContentKind.unknown), same(forumHandler));
  });
}

class _StubFavoriteContentIngestHandler implements FavoriteContentIngestHandler {
  const _StubFavoriteContentIngestHandler({
    required this.kind,
  });

  @override
  final ThreadContentKind kind;

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {}
}
