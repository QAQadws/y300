import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/search/presentation/widgets/forum_search_result_card.dart';
import 'package:y300/shared/widgets/inline_search_app_bar.dart';

void main() {
  testWidgets('ForumSearchPage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: AppTheme.dark(),
        home: ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(
              _FakeDiscuzSearchService(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              ValueNotifier<ComicSearchRefreshQueueSnapshot>(
                ComicSearchRefreshQueueSnapshot.empty,
              ),
            ),
          ],
          child: const ForumSearchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(InlineSearchAppBar), findsOneWidget);
    expect(find.byKey(const Key('forum-search-input')), findsOneWidget);
    expect(find.byKey(const Key('forum-search-submit-button')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('forum-search-input')),
        matching: find.byType(AppBar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ForumHomePage opens ForumSearchPage from app bar action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          discuzSearchServiceProvider.overrideWithValue(
            _FakeDiscuzSearchService(),
          ),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: const LocalizedTestApp(home: ForumHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-home-search-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('forum-home-search-button')));
    await tester.pumpAndSettle();

    expect(find.byType(InlineSearchAppBar), findsOneWidget);
    expect(find.byKey(const Key('forum-search-input')), findsOneWidget);
  });

  testWidgets(
    'ForumSearchPage blocks search while comic search queue is active',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _queueEntry(id: 1, title: '排队漫画'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _FakeDiscuzSearchService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '测试关键词',
      );
      await tester.pump();
      expect(searchService.searchCallCount, 0);
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();

      expect(searchService.searchCallCount, 0);
      expect(find.text('《排队漫画》正在等待搜索，预计 11 秒'), findsOneWidget);
      expect(find.text('测试关键词'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumSearchPage searches normally when comic search queue is empty',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '搜索结果',
              url: 'thread-301-1-1.html',
              fid: '30',
              author: '搜索作者',
              timeText: '2026-08-11',
            ),
          ],
          rateLimited: false,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '测试关键词',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();
      await tester.pump();

      expect(searchService.searchCallCount, 1);
      expect(searchService.lastKeyword, '测试关键词');
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.byKey(const Key('forum-search-result-301')), findsOneWidget);
      expect(find.text('搜索作者 · 2026-08-11'), findsOneWidget);
      expect(find.text('TID：301'), findsOneWidget);
      final resultList = find.byKey(const Key('forum-search-result-list'));
      expect(
        find.descendant(of: resultList, matching: find.byType(ListTile)),
        findsNothing,
      );
      expect(
        find.descendant(of: resultList, matching: find.byType(Divider)),
        findsNothing,
      );
    },
  );

  testWidgets('ForumSearchPage uses parsed-forum list spacing', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    final searchService = _FakeDiscuzSearchService(
      response: const DiscuzSearchResponse(
        items: <DiscuzSearchResultItem>[
          DiscuzSearchResultItem(
            tid: '1',
            title: '第一条结果',
            url: 'thread-1-1-1.html',
            fid: '30',
          ),
          DiscuzSearchResultItem(
            tid: '2',
            title: '第二条结果',
            url: 'thread-2-1-1.html',
            fid: '30',
          ),
        ],
        rateLimited: false,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );

    await tester.enterText(find.byKey(const Key('forum-search-input')), '间距');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('forum-search-result-list')),
    );
    expect(list.padding, const EdgeInsets.fromLTRB(10, 8, 10, 16));
    expect(find.byType(ForumSearchResultCard), findsNWidgets(2));
    final firstBottom = tester
        .getBottomLeft(find.byKey(const Key('forum-search-result-1')))
        .dy;
    final secondTop = tester
        .getTopLeft(find.byKey(const Key('forum-search-result-2')))
        .dy;
    expect(secondTop - firstBottom, 8);
  });

  testWidgets(
    'ForumSearchPage shows scheduler wait when an interactive search is queued',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _QueuedForumSearchService();
      addTearDown(searchService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '新的搜索',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();

      expect(searchService.searchCallCount, 0);
      expect(find.text('后台搜索 正在等待搜索，预计 10.5 秒'), findsOneWidget);
    },
  );

  testWidgets('ForumSearchPage submits from the keyboard search action', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final searchService = _FakeDiscuzSearchService();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );
    await tester.pump();

    final input = find.byKey(const Key('forum-search-input'));
    await tester.enterText(input, '键盘搜索');
    expect(searchService.searchCallCount, 0);
    await tester.showKeyboard(input);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(searchService.searchCallCount, 1);
    expect(searchService.lastKeyword, '键盘搜索');
  });

  testWidgets('ForumSearchPage clear action resets query results and paging', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final searchService = _FakeDiscuzSearchService(
      response: const DiscuzSearchResponse(
        items: <DiscuzSearchResultItem>[
          DiscuzSearchResultItem(
            tid: '301',
            title: '待清空结果',
            url: 'thread-301-1-1.html',
            fid: '30',
          ),
        ],
        rateLimited: false,
        nextPageUrl: 'search.php?page=2',
      ),
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );

    await tester.enterText(find.byKey(const Key('forum-search-input')), '关键词');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('待清空结果'), findsOneWidget);
    expect(searchService.fetchNextPageCallCount, 1);
    expect(
      find.byKey(const Key('forum-search-load-more-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('forum-search-clear-button')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('forum-search-input')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.text('待清空结果'), findsNothing);
    expect(
      find.byKey(const Key('forum-search-load-more-button')),
      findsNothing,
    );
  });

  testWidgets('ForumSearchPage ignores stale search results after resubmit', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final searchService = _ControllableForumSearchService();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );

    final input = find.byKey(const Key('forum-search-input'));
    await tester.enterText(input, '旧查询');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pump();
    expect(searchService.searchRequests, hasLength(1));

    await tester.enterText(input, '新查询');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pump();
    expect(searchService.searchRequests, hasLength(2));

    searchService.searchRequests[1].complete(
      _searchResponse(title: '新结果', tid: '2'),
    );
    await tester.pump();
    searchService.searchRequests[0].complete(
      _searchResponse(title: '过期结果', tid: '1'),
    );
    await tester.pump();

    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('过期结果'), findsNothing);
  });

  testWidgets('ForumSearchPage ignores stale load-more results', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final searchService = _DeferredLoadMoreSearchService();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );

    final input = find.byKey(const Key('forum-search-input'));
    await tester.enterText(input, '旧查询');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pump();
    await tester.pump();
    expect(searchService.loadMoreCallCount, 1);

    await tester.enterText(input, '新查询');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('新查询结果'), findsOneWidget);

    searchService.loadMoreRequest.complete(
      _searchResponse(title: '过期分页结果', tid: '3'),
    );
    await tester.pump();

    expect(find.text('新查询结果'), findsOneWidget);
    expect(find.text('过期分页结果'), findsNothing);
  });

  testWidgets(
    'ForumSearchPage loads once when remaining extent reaches threshold',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      final searchService = _ControlledPaginationSearchService(
        initialResponse: DiscuzSearchResponse(
          items: _searchItems(30, prefix: '初始结果'),
          rateLimited: false,
          nextPageUrl: 'https://bbs.yamibo.com/search.php?page=2',
        ),
      );
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '分页搜索',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pumpAndSettle();

      expect(searchService.loadMoreUrls, isEmpty);
      expect(
        find.byKey(const Key('forum-search-load-more-button')),
        findsNothing,
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('forum-search-result-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(300));

      scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 300);
      await tester.pump();
      expect(searchService.loadMoreUrls, isEmpty);

      scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 200);
      await tester.pump();
      expect(searchService.loadMoreUrls, hasLength(1));

      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(searchService.loadMoreUrls, hasLength(1));
      expect(
        find.byKey(const Key('forum-search-load-more-progress')),
        findsOneWidget,
      );

      searchService.loadMoreRequests.single.complete(
        _searchResponse(title: '自动追加结果', tid: '99'),
      );
      await tester.pumpAndSettle();

      expect(find.text('自动追加结果'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-search-load-more-progress')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'ForumSearchPage fills a short viewport through sequential next pages',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      final searchService = _SequentialPaginationSearchService(
        initialResponse: _searchResponse(
          title: '第一页',
          tid: '1',
          nextPageUrl: 'https://bbs.yamibo.com/search.php?page=2',
        ),
        pages: <String, DiscuzSearchResponse>{
          'https://bbs.yamibo.com/search.php?page=2': _searchResponse(
            title: '第二页',
            tid: '2',
            nextPageUrl: 'https://bbs.yamibo.com/search.php?page=3',
          ),
          'https://bbs.yamibo.com/search.php?page=3': _searchResponse(
            title: '第三页',
            tid: '3',
          ),
        },
      );
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '短列表',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pumpAndSettle();

      expect(searchService.loadMoreUrls, <String>[
        'https://bbs.yamibo.com/search.php?page=2',
        'https://bbs.yamibo.com/search.php?page=3',
      ]);
      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('第三页'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-search-load-more-button')),
        findsNothing,
      );
    },
  );

  testWidgets('ForumSearchPage stops when the server repeats a page URL', (
    tester,
  ) async {
    const repeatedUrl = 'https://bbs.yamibo.com/search.php?page=2';
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final searchService = _SequentialPaginationSearchService(
      initialResponse: _searchResponse(
        title: '第一页',
        tid: '1',
        nextPageUrl: repeatedUrl,
      ),
      pages: <String, DiscuzSearchResponse>{
        repeatedUrl: _searchResponse(
          title: '重复分页结果',
          tid: '2',
          nextPageUrl: repeatedUrl,
        ),
      },
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(searchService),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: ForumSearchPage()),
      ),
    );

    await tester.enterText(find.byKey(const Key('forum-search-input')), '重复分页');
    await tester.pump();
    await tester.tap(find.byKey(const Key('forum-search-submit-button')));
    await tester.pumpAndSettle();

    expect(searchService.loadMoreUrls, <String>[repeatedUrl]);
    expect(find.text('重复分页结果'), findsOneWidget);
    expect(
      find.byKey(const Key('forum-search-load-more-progress')),
      findsNothing,
    );
  });

  testWidgets(
    'ForumSearchPage pauses automatic paging after failure and retries manually',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      final searchService = _RetryPaginationSearchService();
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '失败重试',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pumpAndSettle();

      expect(searchService.loadMoreCallCount, 1);
      expect(find.text('已有结果'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-search-load-more-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-search-load-more-button')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 1));
      expect(searchService.loadMoreCallCount, 1);

      await tester.tap(find.byKey(const Key('forum-search-load-more-button')));
      await tester.pumpAndSettle();

      expect(searchService.loadMoreCallCount, 2);
      expect(find.text('重试追加结果'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-search-load-more-error')),
        findsNothing,
      );
    },
  );

  testWidgets('ForumSearchPage localizes Traditional Chinese chrome', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          discuzSearchServiceProvider.overrideWithValue(
            _FakeDiscuzSearchService(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: ForumSearchPage(),
        ),
      ),
    );

    expect(find.text('輸入關鍵字'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('forum-search-submit-button')),
          )
          .tooltip,
      '搜尋',
    );
  });
}

ComicSearchRefreshQueueEntry _queueEntry({
  required int id,
  required String title,
}) {
  return ComicSearchRefreshQueueEntry(
    id: id,
    comicId: 'comic:$id',
    title: title,
    request: ComicEpisodeRefreshRequest(
      comicId: 'comic:$id',
      sourceTid: '$id',
      displayTitle: title,
    ),
    origin: ComicSearchRefreshOrigin.favoriteSync,
    status: ComicSearchRefreshQueueStatus.pending,
    attempts: 0,
    availableAt: DateTime(2026, 5, 16),
    createdAt: DateTime(2026, 5, 16),
    updatedAt: DateTime(2026, 5, 16),
  );
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ForumHomeCacheEntry?> readCachedPayload({
    required DocumentRequestProfile requestProfile,
  }) async {
    return null;
  }

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
    return ApiSuccess(
      ForumHomePayload(
        forumIndex: ForumIndexData(
          categories: [
            ForumCategory(fid: '1', name: '综合区', forums: ['2']),
          ],
          forums: [
            ForumItem(
              fid: '2',
              name: '公告区',
              threads: 1,
              posts: 1,
              todayPosts: 0,
              description: '',
              icon: '',
              subForums: const [],
            ),
          ],
        ),
        isLoggedIn: false,
        favoriteForums: const [],
        homeSections: const [
          ForumHomeSectionData(
            title: '综合区',
            kind: ForumHomeSectionKind.regular,
            items: [
              ForumHomeForumData(
                fid: '2',
                title: '公告区',
                description: '',
                todayPosts: null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      SessionInfo(uid: '0', username: '', formhash: '', isLoggedIn: false),
    );
  }

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    throw StateError('login is not part of this test');
  }

  @override
  Future<void> logout() async {
    throw StateError('logout is not part of this test');
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    throw StateError('verifyAuthByForumIndex is not part of this test');
  }
}

class _FakeDiscuzSearchService implements ForumSearchService {
  _FakeDiscuzSearchService({
    this.response = const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    ),
  });

  final DiscuzSearchResponse response;
  int searchCallCount = 0;
  int fetchNextPageCallCount = 0;
  String? lastKeyword;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    searchCallCount++;
    lastKeyword = keyword;
    return response;
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    fetchNextPageCallCount++;
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}

DiscuzSearchResponse _searchResponse({
  required String title,
  required String tid,
  String? nextPageUrl,
}) {
  return DiscuzSearchResponse(
    items: <DiscuzSearchResultItem>[
      DiscuzSearchResultItem(
        tid: tid,
        title: title,
        url: 'thread-$tid-1-1.html',
        fid: '30',
      ),
    ],
    rateLimited: false,
    nextPageUrl: nextPageUrl,
  );
}

List<DiscuzSearchResultItem> _searchItems(int count, {required String prefix}) {
  return List<DiscuzSearchResultItem>.generate(count, (index) {
    final tid = '${index + 1}';
    return DiscuzSearchResultItem(
      tid: tid,
      title: '$prefix $tid',
      url: 'thread-$tid-1-1.html',
      fid: '30',
    );
  });
}

class _ControlledPaginationSearchService implements ForumSearchService {
  _ControlledPaginationSearchService({required this.initialResponse});

  final DiscuzSearchResponse initialResponse;
  final List<String> loadMoreUrls = <String>[];
  final List<Completer<DiscuzSearchResponse>> loadMoreRequests =
      <Completer<DiscuzSearchResponse>>[];

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    return initialResponse;
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) {
    loadMoreUrls.add(nextPageUrl);
    final completer = Completer<DiscuzSearchResponse>();
    loadMoreRequests.add(completer);
    return completer.future;
  }
}

class _SequentialPaginationSearchService implements ForumSearchService {
  _SequentialPaginationSearchService({
    required this.initialResponse,
    required this.pages,
  });

  final DiscuzSearchResponse initialResponse;
  final Map<String, DiscuzSearchResponse> pages;
  final List<String> loadMoreUrls = <String>[];

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    return initialResponse;
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    loadMoreUrls.add(nextPageUrl);
    final response = pages[nextPageUrl];
    if (response == null) {
      throw StateError('Unexpected next page: $nextPageUrl');
    }
    return response;
  }
}

class _RetryPaginationSearchService implements ForumSearchService {
  int loadMoreCallCount = 0;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    return _searchResponse(
      title: '已有结果',
      tid: '1',
      nextPageUrl: 'https://bbs.yamibo.com/search.php?page=2',
    );
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    loadMoreCallCount++;
    if (loadMoreCallCount == 1) {
      throw StateError('temporary paging failure');
    }
    return _searchResponse(title: '重试追加结果', tid: '2');
  }
}

class _ControllableForumSearchService implements ForumSearchService {
  final List<Completer<DiscuzSearchResponse>> searchRequests =
      <Completer<DiscuzSearchResponse>>[];

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) {
    final completer = Completer<DiscuzSearchResponse>();
    searchRequests.add(completer);
    return completer.future;
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}

class _DeferredLoadMoreSearchService implements ForumSearchService {
  final Completer<DiscuzSearchResponse> loadMoreRequest =
      Completer<DiscuzSearchResponse>();
  int loadMoreCallCount = 0;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    if (keyword == '旧查询') {
      return _searchResponse(
        title: '旧查询结果',
        tid: '1',
        nextPageUrl: 'search.php?page=2',
      );
    }
    return _searchResponse(title: '新查询结果', tid: '2');
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) {
    loadMoreCallCount++;
    return loadMoreRequest.future;
  }
}

class _QueuedForumSearchService
    implements ForumSearchService, ForumSearchQueueStateReader {
  final ValueNotifier<ForumSearchSchedulerSnapshot> _snapshot =
      ValueNotifier<ForumSearchSchedulerSnapshot>(
        const ForumSearchSchedulerSnapshot(
          pendingCount: 1,
          running: true,
          headKeyword: '后台搜索',
          estimatedWait: Duration(milliseconds: 10500),
        ),
      );
  int searchCallCount = 0;

  @override
  ValueListenable<ForumSearchSchedulerSnapshot> get snapshot => _snapshot;

  void dispose() => _snapshot.dispose();

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    searchCallCount++;
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}
