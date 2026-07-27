import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
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
              result: _result(ComicCommentLoadStatus.empty),
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
              result: _result(ComicCommentLoadStatus.failure),
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
              result: _result(ComicCommentLoadStatus.partialFailure),
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
              result: ComicCommentLoadResult(
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
    );
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ComicCommentCard).evaluate().length, lessThan(40));
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
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
