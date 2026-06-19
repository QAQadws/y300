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
    testWidgets('stays buildable first then renders list', (tester) async {
      final completer = Completer<ApiResult<ForumDisplayData>>();
      final repository = _FakeForumDisplayRepository(
        (fid, page, query) => completer.future,
      );

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('forum-display-list')), findsNothing);

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
      expect(find.text('公告区'), findsWidgets);
      expect(find.text('第1页'), findsOneWidget);
    });

    testWidgets('loads next page when tapping load more', (tester) async {
      var callCount = 0;
      final repository = _FakeForumDisplayRepository((_, page, query) async {
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

      expect(
        find.byKey(const Key('forum-display-load-more-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('forum-display-load-more-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('帖子A'), findsNothing);
      expect(find.text('帖子B'), findsOneWidget);
      expect(callCount, 2);
    });

    testWidgets('filter and thread tag taps reload using link query', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        final typeid = query?.parameters['typeid'];
        return ApiSuccess(
          _displayData(
            page: page,
            total: 10,
            threads: [
              ForumThreadSummary(
                tid: typeid == '65' ? 'top-filtered' : 'tag-filtered',
                subject: typeid == '65' ? '公告筛选结果' : '分类筛选结果',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
                sourceTagName: '長篇連載',
                sourceTagUrl:
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=69&mobile=2',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.byKey(const Key('forum-display-filter-公告')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.parameters['filter'], 'typeid');
      expect(repository.lastQuery?.parameters['typeid'], '65');
      expect(find.text('公告筛选结果'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-thread-tag-top-filtered')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.parameters['typeid'], '69');
      expect(find.text('分类筛选结果'), findsOneWidget);
    });

    testWidgets('pinned entry opens thread detail', (tester) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            topEntries: const <ForumDisplayTopEntry>[
              ForumDisplayTopEntry(
                title: '置顶跳转',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=535389&mobile=2',
                tid: '535389',
                badgeLabel: '置顶',
              ),
            ],
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.text('置顶跳转'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('置顶跳转'), findsWidgets);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
    });

    testWidgets('current page button opens picker and loads selected page', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 10,
            lastPage: 8,
            threads: [
              ForumThreadSummary(
                tid: 'page-$page',
                subject: '第$page页结果',
                author: 'alice',
                replies: 0,
                views: 1,
                dateline: 'today',
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(
        find.byKey(const Key('forum-display-current-page-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('forum-display-page-input')),
        '3',
      );
      await tester.tap(
        find.byKey(const Key('forum-display-page-confirm-button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(repository.lastQuery?.page, 3);
      expect(find.text('第3页结果'), findsOneWidget);
    });

    testWidgets('renders HTML-first forum chrome and pinned entries', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((_, page, query) async {
        return ApiSuccess(
          _displayData(
            page: page,
            total: 52718,
            headImageUrl:
                'https://bbs.yamibo.com/data/attachment/album/202603/02/head.png',
            threads: [
              ForumThreadSummary(
                tid: '572604',
                subject: '[个人汉化]测试标题',
                author: 'nkdndixnx',
                replies: 0,
                views: 119,
                dateline: '2026-6-18 14:42',
                excerpt: '请勿随意转载，也请别在外网提及，谢谢',
                sourceTagName: '長篇連載',
                badgeLabel: '关闭的主题',
                isLocked: true,
              ),
            ],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-head-image')), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-display-compose-button')),
        findsOneWidget,
      );

      await tester.drag(
        find.byKey(const Key('forum-display-list')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();

      expect(find.text('公告'), findsWidgets);
      expect(find.text('欢迎光临。'), findsOneWidget);
      expect(find.text('[个人汉化]测试标题'), findsOneWidget);
      expect(find.textContaining('请勿随意转载'), findsOneWidget);
      expect(find.text('#長篇連載'), findsOneWidget);
    });

    testWidgets('renders sub forum entry and opens nested forum display', (
      tester,
    ) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        if (fid == '52') {
          return ApiSuccess(
            ForumDisplayData(
              fid: '52',
              forumName: '百合会最萌世界杯专版！',
              currentPage: 1,
              perPage: 20,
              totalThreads: 0,
              threads: const <ForumThreadSummary>[],
            ),
          );
        }

        return ApiSuccess(
          _displayData(
            page: page,
            total: 1,
            subForums: const <ForumDisplaySubForum>[
              ForumDisplaySubForum(
                fid: '52',
                title: '百合会最萌世界杯专版！',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=52&mobile=2',
                iconUrl:
                    'https://bbs.yamibo.com/data/attachment/common/9a/common_52_icon.gif',
              ),
            ],
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(const Key('forum-display-sub-forums')), findsOneWidget);
      expect(find.text('子版块'), findsOneWidget);
      expect(find.text('百合会最萌世界杯专版！'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-display-sub-forum-52')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.canPop(), isTrue);
      expect(find.text('百合会最萌世界杯专版！'), findsWidgets);
      expect(repository.lastQuery?.fid, '52');
    });

    testWidgets('shows search-in-forum action when fid is 30', (tester) async {
      final repository = _FakeForumDisplayRepository((fid, page, query) async {
        return ApiSuccess(
          _displayData(
            page: 1,
            total: 1,
            threads: const <ForumThreadSummary>[],
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumDisplayRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: ForumDisplayPage(fid: '30', title: '漫画区'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('forum-display-search-button')),
        findsOneWidget,
      );
    });
  });
}

Widget _buildTestApp(ForumDisplayRepository repository) {
  return ProviderScope(
    overrides: [forumDisplayRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(
      home: ForumDisplayPage(fid: '2', title: '公告区'),
    ),
  );
}

ForumDisplayData _displayData({
  required int page,
  required int total,
  required List<ForumThreadSummary> threads,
  List<ForumDisplayTopEntry>? topEntries,
  String? headImageUrl,
  List<ForumDisplaySubForum>? subForums,
  int? lastPage,
}) {
  return ForumDisplayData(
    fid: '2',
    forumName: '公告区',
    currentPage: page,
    perPage: 1,
    totalThreads: total,
    headImageUrl: headImageUrl,
    todayPosts: 3,
    rank: 1,
    lastPage: lastPage,
    previousPageUrl: page > 1
        ? 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&page=${page - 1}&mobile=2'
        : null,
    nextPageUrl: page < (lastPage ?? total)
        ? 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&page=${page + 1}&mobile=2'
        : null,
    hasMoreOverride: page < (lastPage ?? total),
    primaryFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '全部',
        url: 'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&mobile=2',
        isSelected: true,
      ),
      ForumDisplayFilterItem(
        label: '最新',
        url:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=lastpost&mobile=2',
      ),
    ],
    typeFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '公告',
        url:
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=2&filter=typeid&typeid=65&mobile=2',
        typeid: '65',
      ),
    ],
    subForums: subForums ?? const <ForumDisplaySubForum>[],
    topEntries:
        topEntries ??
        const <ForumDisplayTopEntry>[
          ForumDisplayTopEntry(
            title: '欢迎光临。',
            url: 'https://bbs.yamibo.com/forum.php?mod=announcement&id=17',
            badgeLabel: '公告',
            isAnnouncement: true,
          ),
        ],
    threads: threads,
  );
}

class _FakeForumDisplayRepository implements ForumDisplayRepository {
  _FakeForumDisplayRepository(this._loader);

  final Future<ApiResult<ForumDisplayData>> Function(
    String fid,
    int page,
    ForumDisplayQuery? query,
  )
  _loader;
  ForumDisplayQuery? lastQuery;

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplay({
    required String fid,
    int page = 1,
  }) {
    return _loader(fid, page, null);
  }

  @override
  Future<ApiResult<ForumDisplayData>> getForumDisplayByQuery(
    ForumDisplayQuery query,
  ) {
    lastQuery = query;
    return _loader(query.fid, query.page, query);
  }
}
