import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/data/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';

void main() {
  group('ForumDisplayPage', () {
    testWidgets('shows skeleton first then list', (tester) async {
      final completer = Completer<ApiResult<ForumDisplayData>>();
      final repository = _FakeForumDisplayRepository((fid, page) => completer.future);

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byKey(const Key('forum-display-skeleton')), findsOneWidget);

      completer.complete(
        ApiSuccess(
          _displayData(
            page: 1,
            total: 2,
            threads: [
              ForumThreadSummary(
                tid: '100',
                subject: '帖子A',
                author: 'alice',
                replies: 1,
                views: 5,
                dateline: 'today',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-list')), findsOneWidget);
      expect(find.text('帖子A'), findsOneWidget);
    });

    testWidgets('loads next page when tapping load more', (tester) async {
      var callCount = 0;
      final repository = _FakeForumDisplayRepository((_, page) async {
        callCount++;
        if (page == 1) {
          return ApiSuccess(
            _displayData(
              page: 1,
              total: 2,
              threads: [
                ForumThreadSummary(
                  tid: '100',
                  subject: '帖子A',
                  author: 'alice',
                  replies: 1,
                  views: 5,
                  dateline: 'today',
                ),
              ],
            ),
          );
        }

        return ApiSuccess(
          _displayData(
            page: 2,
            total: 2,
            threads: [
              ForumThreadSummary(
                tid: '101',
                subject: '帖子B',
                author: 'bob',
                replies: 2,
                views: 6,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-load-more-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('forum-display-load-more-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('帖子A'), findsOneWidget);
      expect(find.text('帖子B'), findsOneWidget);
      expect(callCount, 2);
    });
  });
}

Widget _buildTestApp(ForumDisplayRepository repository) {
  return ProviderScope(
    overrides: [
      forumDisplayRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: ForumDisplayPage(fid: '2', title: '公告区'),
    ),
  );
}

ForumDisplayData _displayData({
  required int page,
  required int total,
  required List<ForumThreadSummary> threads,
}) {
  return ForumDisplayData(
    fid: '2',
    forumName: '公告区',
    currentPage: page,
    perPage: 1,
    totalThreads: total,
    threads: threads,
  );
}

class _FakeForumDisplayRepository implements ForumDisplayRepository {
  _FakeForumDisplayRepository(this._loader);

  final Future<ApiResult<ForumDisplayData>> Function(String fid, int page) _loader;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
  }) {
    return _loader(fid, page);
  }
}
