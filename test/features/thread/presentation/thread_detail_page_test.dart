import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

void main() {
  group('ThreadDetailPage', () {
    testWidgets('shows posts and loads more replies', (tester) async {
      var callCount = 0;
      final repository = _FakeThreadRepository((tid, page) async {
        callCount++;
        if (page == 1) {
          return ApiSuccess(
            ThreadDetailData(
              tid: tid,
              fid: '2',
              subject: '测试主题',
              author: 'alice',
              replies: 1,
              views: 12,
              currentPage: 1,
              perPage: 1,
              posts: [
                ThreadPost(
                  pid: 'p1',
                  author: 'alice',
                  authorId: '1',
                  message: '<p>第一条回复</p>',
                  number: 1,
                  isFirst: true,
                  dateline: 'today',
                ),
              ],
            ),
          );
        }

        return ApiSuccess(
          ThreadDetailData(
            tid: tid,
            fid: '2',
            subject: '测试主题',
            author: 'alice',
            replies: 1,
            views: 12,
            currentPage: 2,
            perPage: 1,
            posts: [
              ThreadPost(
                pid: 'p2',
                author: 'bob',
                authorId: '2',
                message: '<div>第二条回复</div>',
                number: 2,
                isFirst: false,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('thread-detail-list')), findsOneWidget);
      expect(find.text('第一条回复'), findsOneWidget);

      expect(find.byKey(const Key('thread-detail-load-more-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('thread-detail-load-more-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('第一条回复'), findsOneWidget);
      expect(find.text('第二条回复'), findsOneWidget);
      expect(callCount, 2);
    });
  });
}

Widget _buildTestApp(ThreadRepository repository) {
  return ProviderScope(
    overrides: [threadRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(
      home: ThreadDetailPage(tid: '100', subject: '测试主题'),
    ),
  );
}

class _FakeThreadRepository implements ThreadRepository {
  _FakeThreadRepository(this._loader);

  final Future<ApiResult<ThreadDetailData>> Function(String tid, int page) _loader;

  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({required String tid, int page = 1}) {
    return _loader(tid, page);
  }
}
