import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/search/domain/repositories/forum_search_repository.dart';

void main() {
  testWidgets('ForumSearchPage builds search chrome', (tester) async {
    final coordinator = _FakeForumSearchCoordinator();
    await tester.pumpWidget(_buildApp(coordinator));
    addTearDown(coordinator.dispose);

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('forum-search-input')), findsOneWidget);
    expect(find.byKey(const Key('forum-search-submit-button')), findsOneWidget);
  });

  testWidgets('search builds a source-neutral query and renders topics', (
    tester,
  ) async {
    final coordinator = _FakeForumSearchCoordinator(
      topics: const <ForumSearchTopicSummary>[
        ForumSearchTopicSummary(
          tid: '100',
          title: '测试漫画 第1话',
          forumId: '30',
          forumName: '漫画版',
          authorName: '作者',
          publishedAtText: '今天',
        ),
      ],
    );
    await tester.pumpWidget(
      _buildApp(
        coordinator,
        page: const ForumSearchPage(
          scope: ForumSearchScope.currentForum,
          forumId: '30',
        ),
      ),
    );
    addTearDown(coordinator.dispose);

    await tester.enterText(
      find.byKey(const Key('forum-search-input')),
      '  测试漫画  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(coordinator.queries.single.normalizedKeyword, '测试漫画');
    expect(coordinator.queries.single.scope, ForumSearchScope.currentForum);
    expect(coordinator.queries.single.normalizedForumId, '30');
    expect(find.text('测试漫画 第1话'), findsOneWidget);
  });

  testWidgets('refresh failure keeps the previous result visible', (
    tester,
  ) async {
    final coordinator = _FakeForumSearchCoordinator(
      topics: const <ForumSearchTopicSummary>[
        ForumSearchTopicSummary(tid: '100', title: '旧结果'),
      ],
    );
    await tester.pumpWidget(_buildApp(coordinator));
    addTearDown(coordinator.dispose);

    final input = find.byKey(const Key('forum-search-input'));
    await tester.enterText(input, '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('旧结果'), findsOneWidget);

    coordinator.failNext = true;
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('旧结果'), findsOneWidget);
  });
}

Widget _buildApp(
  _FakeForumSearchCoordinator coordinator, {
  ForumSearchPage page = const ForumSearchPage(),
}) {
  return LocalizedTestApp(
    theme: AppTheme.dark(),
    home: ProviderScope(
      overrides: [
        forumSearchCoordinatorProvider.overrideWithValue(coordinator),
        comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
          ValueNotifier<ComicSearchRefreshQueueSnapshot>(
            ComicSearchRefreshQueueSnapshot.empty,
          ),
        ),
      ],
      child: page,
    ),
  );
}

final class _FakeForumSearchCoordinator
    implements ForumSearchCoordinator, ForumSearchReadQueueStateReader {
  _FakeForumSearchCoordinator({
    this.topics = const <ForumSearchTopicSummary>[],
  });

  final List<ForumSearchTopicSummary> topics;
  final List<ForumSearchQuery> queries = <ForumSearchQuery>[];
  final ValueNotifier<ForumSearchReadSchedulerSnapshot> _snapshot =
      ValueNotifier<ForumSearchReadSchedulerSnapshot>(
        ForumSearchReadSchedulerSnapshot.empty,
      );
  bool failNext = false;

  @override
  ValueListenable<ForumSearchReadSchedulerSnapshot> get snapshot => _snapshot;

  @override
  Future<ForumSearchExecution> search(
    ForumSearchQuery query, {
    bool enforceRateLimit = true,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    queries.add(query);
    if (failNext) {
      failNext = false;
      return const ForumSearchExecution.read(
        DataReadFailure<ForumSearchData, ForumSearchReadCapabilities>(
          kind: DataReadFailureKind.network,
          code: 'test_search_failure',
          diagnosticMessage: 'Search failed.',
        ),
      );
    }
    return ForumSearchExecution.read(_success(query));
  }

  @override
  Future<ForumSearchExecution> loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page,
  ) async {
    return ForumSearchExecution.read(_success(query, currentPage: page.page));
  }

  DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities> _success(
    ForumSearchQuery query, {
    int currentPage = 1,
  }) {
    final data = ForumSearchData(
      query: query.normalized(),
      topics: topics,
      pagination: ForumSearchPagination(currentPage: currentPage),
    );
    return DataReadSuccess(
      data: data,
      capabilities: ForumSearchReadCapabilities(
        values: DataCapabilitySet<ForumSearchCapability>.supported(
          ForumSearchCapability.values,
        ),
        paginationPrecision: PaginationPrecision.unknown,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }

  void dispose() => _snapshot.dispose();
}
