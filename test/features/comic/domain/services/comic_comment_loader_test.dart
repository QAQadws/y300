import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import '../../data/comic_comment_fixtures.dart';

void main() {
  test(
    'production comments consume the HTML detail provider and retain all floor data',
    () async {
      final repo = CommentDetailRepository();
      final container = ProviderContainer(
        overrides: [threadRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(comicCommentLoaderProvider)
          .loadPage(sourceTid: '100');
      expect(repo.calls, [1]);
      expect(result.items.map((p) => p.pid), ['1', '2']);
      final first = result.items.first;
      expect(first.post.isFirst, isTrue);
      expect(first.post.ratingSummary?.scoreText, '+2');
      expect(first.post.comments, hasLength(1));
      expect(first.post.commentUrl, isNotEmpty);
      expect(first.post.message, contains('blockquote'));
      expect(result.reads[1]?.metadata.origin, DataReadOrigin.network);
      expect(result.nextPage, 2);
    },
  );
  test('loads only requested pages and honors the HTML last page', () async {
    final repo = CommentDetailRepository();
    final loader = DefaultComicCommentLoader(repository: repo);
    final page = await loader.loadPage(sourceTid: '100', page: 3);
    expect(repo.calls, [3]);
    expect(page.nextPage, isNull);
    expect(page.items.first.sourcePage, 3);
  });
  test(
    'concurrent readers share a page flight, cancellation only releases its waiter',
    () async {
      final pending = Completer<CommentDetailRead>();
      final repo = CommentDetailRepository(respond: (_) => pending.future);
      final loader = DefaultComicCommentLoader(repository: repo);
      final token = ComicCommentCancellationToken();
      final one = loader.loadPage(sourceTid: '100', cancellationToken: token);
      final two = loader.loadPage(sourceTid: '100');
      token.cancel();
      expect((await one).status, ComicCommentLoadStatus.cancelled);
      pending.complete(commentDetailPage());
      expect((await two).items, hasLength(2));
      expect(repo.calls, [1]);
    },
  );
  test(
    'invalidation detaches an old flight and never introduces a private result cache',
    () async {
      final old = Completer<CommentDetailRead>();
      var count = 0;
      final repo = CommentDetailRepository(
        respond: (_) => ++count == 1
            ? old.future
            : commentDetailPage(posts: [commentPost(2)]),
      );
      final loader = DefaultComicCommentLoader(repository: repo);
      final stale = loader.loadPage(sourceTid: '100');
      loader.invalidate('100');
      expect((await loader.loadPage(sourceTid: '100')).items.single.pid, '2');
      old.complete(commentDetailPage());
      await stale;
      expect((await loader.loadPage(sourceTid: '100')).items.single.pid, '2');
      expect(repo.calls, [1, 1, 1]);
    },
  );
  test(
    'invalid input and mismatched identities fail without pretending to be empty',
    () async {
      final repo = CommentDetailRepository(
        respond: (_) => commentDetailPage(page: 2),
      );
      final loader = DefaultComicCommentLoader(repository: repo);
      expect(
        (await loader.loadPage(sourceTid: 'invalid')).errorCode,
        ComicCommentLoadErrorCode.invalidSourceTid,
      );
      expect(repo.calls, isEmpty);
      expect(
        (await loader.loadPage(sourceTid: '100')).errorCode,
        ComicCommentLoadErrorCode.invalidPageResponse,
      );
      final mismatch = DefaultComicCommentLoader(
        repository: CommentDetailRepository(
          respond: (_) => commentDetailPage(tid: '999'),
        ),
      );
      expect(
        (await mismatch.loadPage(sourceTid: '100')).status,
        ComicCommentLoadStatus.failure,
      );
    },
  );
  test(
    'timeouts and authorization keep distinct retry classifications',
    () async {
      final timeout = DefaultComicCommentLoader(
        repository: CommentDetailRepository(
          respond: (_) => Completer<CommentDetailRead>().future,
        ),
        pageRequestTimeout: const Duration(milliseconds: 1),
      );
      expect(
        (await timeout.loadPage(sourceTid: '100')).errorCode,
        ComicCommentLoadErrorCode.pageTimeout,
      );
      final denied = DefaultComicCommentLoader(
        repository: CommentDetailRepository(
          respond: (_) => const DataReadFailure(
            kind: DataReadFailureKind.unauthorized,
            diagnosticMessage: 'private payload',
          ),
        ),
      );
      final result = await denied.loadPage(sourceTid: '100');
      expect(result.errorCode, ComicCommentLoadErrorCode.unauthorized);
      expect(result.isTransientFailure, isFalse);
      expect(result.diagnosticDetail, isNull);
    },
  );
}
