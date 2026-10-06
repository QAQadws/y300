import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';
import 'package:y300/features/search/data/services/search_rate_limiter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ForumSearchReadScheduler', () {
    test('serializes scheduled searches with the configured cadence', () async {
      var now = DateTime(2026, 5, 16, 12, 0, 0);
      final delays = <Duration>[];
      final repository = _RecordingForumSearchRepository(
        nowProvider: () => now,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final scheduler = ForumSearchReadScheduler(
        repository: repository,
        rateLimiter: SearchRateLimiter(sharedPreferences: preferences),
        nowProvider: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );
      addTearDown(scheduler.dispose);

      final first = scheduler.search(
        const ForumSearchQuery(keyword: 'alpha'),
        enforceRateLimit: false,
      );
      final second = scheduler.search(
        const ForumSearchQuery(keyword: 'beta'),
        enforceRateLimit: false,
      );
      await Future.wait(<Future<ForumSearchExecution>>[first, second]);

      expect(repository.startedKeywords, <String>['alpha', 'beta']);
      expect(
        repository.startedAt[1].difference(repository.startedAt[0]),
        SearchRateLimiter.defaultCooldown,
      );
      expect(delays, <Duration>[SearchRateLimiter.defaultCooldown]);
    });

    test(
      'interactive search reports cooldown without entering the queue',
      () async {
        var now = DateTime(2026, 10, 6, 12);
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final repository = _RecordingForumSearchRepository(
          nowProvider: () => now,
        );
        final scheduler = ForumSearchReadScheduler(
          repository: repository,
          rateLimiter: SearchRateLimiter(
            sharedPreferences: preferences,
            nowProvider: () => now,
          ),
          nowProvider: () => now,
          delay: (_) async =>
              fail('Interactive cooldown must return immediately'),
        );
        addTearDown(scheduler.dispose);

        await scheduler.search(const ForumSearchQuery(keyword: 'alpha'));
        now = now.add(const Duration(seconds: 4));
        final blocked = await scheduler.search(
          const ForumSearchQuery(keyword: 'beta'),
        );

        expect(blocked.retryAfter, const Duration(milliseconds: 6500));
        expect(repository.startedKeywords, ['alpha']);
        expect(scheduler.snapshot.value.active, isFalse);
      },
    );

    test(
      'queued searches wait for the preceding completed search cooldown',
      () async {
        var now = DateTime(2026, 10, 6, 12);
        final delays = <Duration>[];
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final repository = _RecordingForumSearchRepository(
          nowProvider: () => now,
          onLoad: () async {
            now = now.add(const Duration(seconds: 2));
          },
        );
        final scheduler = ForumSearchReadScheduler(
          repository: repository,
          rateLimiter: SearchRateLimiter(
            sharedPreferences: preferences,
            nowProvider: () => now,
          ),
          nowProvider: () => now,
          delay: (duration) async {
            delays.add(duration);
            now = now.add(duration);
          },
        );
        addTearDown(scheduler.dispose);

        final results = await Future.wait([
          for (final keyword in ['alpha', 'beta', 'gamma'])
            scheduler.search(
              ForumSearchQuery(keyword: keyword),
              waitForRateLimit: true,
            ),
        ]);

        expect(
          results.every((result) => result.readResult?.isSuccess ?? false),
          isTrue,
        );
        expect(repository.startedKeywords, ['alpha', 'beta', 'gamma']);
        expect(delays, List.filled(2, SearchRateLimiter.defaultCooldown));
        for (var index = 1; index < repository.startedAt.length; index++) {
          expect(
            repository.startedAt[index].difference(
              repository.startedAt[index - 1],
            ),
            const Duration(milliseconds: 12500),
          );
        }
        expect(scheduler.snapshot.value.active, isFalse);
      },
    );

    test(
      'new scheduler honors remaining persisted cooldown for queued work',
      () async {
        var now = DateTime(2026, 10, 6, 12);
        final delays = <Duration>[];
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final rateLimiter = SearchRateLimiter(
          sharedPreferences: preferences,
          nowProvider: () => now,
        );
        final repository = _RecordingForumSearchRepository(
          nowProvider: () => now,
        );
        final firstScheduler = ForumSearchReadScheduler(
          repository: repository,
          rateLimiter: rateLimiter,
          nowProvider: () => now,
        );
        await firstScheduler.search(const ForumSearchQuery(keyword: 'alpha'));
        firstScheduler.dispose();
        now = now.add(const Duration(seconds: 4));
        final restoredScheduler = ForumSearchReadScheduler(
          repository: repository,
          rateLimiter: rateLimiter,
          nowProvider: () => now,
          delay: (duration) async {
            delays.add(duration);
            now = now.add(duration);
          },
        );
        addTearDown(restoredScheduler.dispose);

        final result = await restoredScheduler.search(
          const ForumSearchQuery(keyword: 'beta'),
          waitForRateLimit: true,
        );

        expect(result.readResult?.isSuccess, isTrue);
        expect(delays, [const Duration(milliseconds: 6500)]);
        expect(repository.startedKeywords, ['alpha', 'beta']);
        expect(
          repository.startedAt[1].difference(repository.startedAt[0]),
          SearchRateLimiter.defaultCooldown,
        );
      },
    );

    test(
      'loadNextPage delegates the opaque page identity to the repository',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final repository = _RecordingForumSearchRepository();
        final scheduler = ForumSearchReadScheduler(
          repository: repository,
          rateLimiter: SearchRateLimiter(sharedPreferences: preferences),
        );
        addTearDown(scheduler.dispose);

        final result = await scheduler.loadNextPage(
          const ForumSearchQuery(keyword: 'alpha'),
          const ForumSearchPageIdentity(token: 'page-2', page: 2),
        );

        expect(result.readResult?.isSuccess, isTrue);
        expect(repository.nextPageCalls, 1);
      },
    );
  });
}

final class _RecordingForumSearchRepository implements ForumSearchRepository {
  _RecordingForumSearchRepository({
    DateTime Function()? nowProvider,
    this.onLoad,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final Future<void> Function()? onLoad;
  final List<String> startedKeywords = <String>[];
  final List<DateTime> startedAt = <DateTime>[];
  int nextPageCalls = 0;

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    startedKeywords.add(query.normalizedKeyword);
    startedAt.add(_nowProvider());
    await onLoad?.call();
    return _success(query, currentPage: 1);
  }

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    nextPageCalls++;
    return _success(query, currentPage: page.page);
  }

  DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities> _success(
    ForumSearchQuery query, {
    required int currentPage,
  }) {
    final data = ForumSearchData(
      query: query.normalized(),
      topics: const <ForumSearchTopicSummary>[],
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
}
