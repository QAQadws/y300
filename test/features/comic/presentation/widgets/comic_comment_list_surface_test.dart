import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_card.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_list_surface.dart';

void main() {
  testWidgets('shows loading, empty and failure states', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(sourceTid: '573279', isLoading: true),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('comic-comment-loading')), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(
              sourceTid: '573279',
              projection: _projection(_result(ComicCommentLoadStatus.empty)),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('comic-comment-empty')), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(
              sourceTid: '573279',
              projection: _projection(_result(ComicCommentLoadStatus.failure)),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('comic-comment-failure-state')),
      findsOneWidget,
    );
  });

  testWidgets('keeps partial items and exposes a retry action', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(
              sourceTid: '573279',
              projection: _projection(
                _result(ComicCommentLoadStatus.partialFailure),
              ),
              onRetry: () => retryCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('comic-comment-list')), findsOneWidget);
    expect(find.byType(ComicCommentCard), findsOneWidget);
    expect(find.text('部分用户'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(
      find.byKey(const Key('comic-comment-failure-state')),
      findsOneWidget,
    );

    await tester.tap(find.text('重试'));
    expect(retryCount, 1);
  });

  testWidgets('constructs comments lazily without reader controls', (
    tester,
  ) async {
    final items = List<ComicCommentItem>.generate(
      1000,
      (index) => _comment(pid: 'p$index', authorName: '用户$index'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(
              sourceTid: '573279',
              projection: _projection(
                ComicCommentLoadResult(
                  sourceTid: '573279',
                  status: ComicCommentLoadStatus.success,
                  items: items,
                  loadedPages: const {1, 2},
                  expectedPages: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ComicCommentCard).evaluate().length, lessThan(40));
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('uses projected rows while retaining raw author identity', (
    tester,
  ) async {
    final source = _comment(pid: 'p8', authorName: '发型用户名');
    final result = ComicCommentLoadResult(
      sourceTid: '573279',
      status: ComicCommentLoadStatus.success,
      items: <ComicCommentItem>[source],
      loadedPages: const <int>{1},
      expectedPages: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ComicCommentListSurface(
              sourceTid: '573279',
              projection: ComicCommentContentProjection(
                sourceResult: result,
                items: <ComicCommentItemProjection>[
                  ComicCommentItemProjection(
                    sourceItem: source,
                    displayMessage: '<p>評論正文</p>',
                    displayDateline: '剛剛',
                  ),
                ],
                mode: TextConversionMode.toTraditional,
                converterId: 'test:traditional',
                sourceRevision: 'test:converted',
                isConverted: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('发型用户名'), findsOneWidget);
    expect(find.text('髮型用戶名'), findsNothing);
    expect(find.text('剛剛'), findsOneWidget);
  });
}

ComicCommentLoadResult _result(ComicCommentLoadStatus status) {
  return ComicCommentLoadResult(
    sourceTid: '573279',
    status: status,
    items: status == ComicCommentLoadStatus.partialFailure
        ? <ComicCommentItem>[_comment(pid: 'p5', authorName: '部分用户')]
        : const <ComicCommentItem>[],
    loadedPages: const {1},
    expectedPages: 2,
  );
}

ComicCommentContentProjection _projection(ComicCommentLoadResult result) {
  return ComicCommentContentProjection.raw(
    result,
    mode: TextConversionMode.none,
    converterId: 'conv:none',
    sourceRevision: 'test:${result.status.name}',
  );
}

ComicCommentItem _comment({required String pid, String authorName = '用户'}) {
  return ComicCommentItem(
    pid: pid,
    authorId: '8',
    authorName: authorName,
    dateline: '刚刚',
    floorNumber: 5,
    rawMessage: '<p>评论</p>',
    avatarUrl: null,
  );
}
