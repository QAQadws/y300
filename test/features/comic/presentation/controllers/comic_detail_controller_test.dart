import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_refresh_outcome_providers.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/controllers/comic_detail_controller.dart';

void main() {
  group('ComicDetailController', () {
    test('refreshEpisodes uses catalog-then-fallback and applier on success', () async {
      final repository = _FakeComicRepository();
      final refreshService = _FakeRefreshService(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.search,
          usedSearch: true,
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
            ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
          ],
        ),
      );
      final applier = _RecordingRefreshOutcomeApplier(
        result: const ComicRefreshApplyResult(
          status: ComicRefreshApplyStatus.applied,
          insertedCount: 2,
          updatedCount: 1,
          totalCount: 3,
          coverPromoted: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(repository),
          comicEpisodeRefreshServiceProvider.overrideWithValue(refreshService),
          comicRefreshOutcomeApplierProvider.overrideWithValue(applier),
          comicReaderFeatureFlagsProvider.overrideWithValue(
            ComicReaderFeatureFlags.defaults,
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = ComicDetailArgs(comicId: 'comic:1');
      final subscription = container.listen(
        comicDetailControllerProvider(args),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(comicDetailControllerProvider(args).future);
      await container
          .read(comicDetailControllerProvider(args).notifier)
          .refreshEpisodes();

      final state = container.read(comicDetailControllerProvider(args)).value!;
      expect(refreshService.catalogThenFallbackCalls, 1);
      expect(refreshService.fetchEpisodeLinksCalls, 0);
      expect(applier.requests, hasLength(1));
      expect(applier.requests.single.comicId, 'comic:1');
      expect(applier.requests.single.sourceTid, '100');
      expect(
        applier.requests.single.reason,
        'comic_detail_controller_refresh_completed',
      );
      expect(applier.requests.single.source, ComicEpisodeRefreshSource.search);
      expect(state.isRefreshing, isFalse);
      expect(state.refreshHint, '章节刷新完成：新增2，更新1');
    });

    test('refreshEpisodes keeps empty-link hint unchanged', () async {
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(
            _FakeRefreshService(
              outcome: const ComicEpisodeRefreshOutcome(
                source: ComicEpisodeRefreshSource.empty,
                links: <ComicEpisodeLink>[],
              ),
            ),
          ),
          comicRefreshOutcomeApplierProvider.overrideWithValue(
            _RecordingRefreshOutcomeApplier(),
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = ComicDetailArgs(comicId: 'comic:1');
      final subscription = container.listen(
        comicDetailControllerProvider(args),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(comicDetailControllerProvider(args).future);
      await container
          .read(comicDetailControllerProvider(args).notifier)
          .refreshEpisodes();

      final state = container.read(comicDetailControllerProvider(args)).value!;
      expect(state.isRefreshing, isFalse);
      expect(state.refreshHint, '未提取到新的章节链接');
    });

    test('refreshEpisodes keeps exception hint unchanged', () async {
      final container = ProviderContainer(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          comicEpisodeRefreshServiceProvider.overrideWithValue(
            const _ThrowingRefreshService(),
          ),
          comicRefreshOutcomeApplierProvider.overrideWithValue(
            _RecordingRefreshOutcomeApplier(),
          ),
        ],
      );
      addTearDown(container.dispose);
      const args = ComicDetailArgs(comicId: 'comic:1');
      final subscription = container.listen(
        comicDetailControllerProvider(args),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(comicDetailControllerProvider(args).future);
      await container
          .read(comicDetailControllerProvider(args).notifier)
          .refreshEpisodes();

      final state = container.read(comicDetailControllerProvider(args)).value!;
      expect(state.isRefreshing, isFalse);
      expect(state.refreshHint, contains('刷新章节失败：'));
      expect(state.refreshHint, contains('refresh failed'));
    });
  });
}

class _FakeRefreshService implements ComicEpisodeRefreshService {
  _FakeRefreshService({required this.outcome});

  final ComicEpisodeRefreshOutcome outcome;
  int catalogThenFallbackCalls = 0;
  int fetchEpisodeLinksCalls = 0;

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return outcome;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    catalogThenFallbackCalls++;
    return outcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    fetchEpisodeLinksCalls++;
    return outcome.links;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return outcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return outcome;
  }
}

class _ThrowingRefreshService implements ComicEpisodeRefreshService {
  const _ThrowingRefreshService();

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }
}

class _RecordingRefreshOutcomeApplier implements ComicRefreshOutcomeApplier {
  _RecordingRefreshOutcomeApplier({
    this.result = const ComicRefreshApplyResult(
      status: ComicRefreshApplyStatus.applied,
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
      coverPromoted: false,
    ),
  });

  final ComicRefreshApplyResult result;
  final List<ComicRefreshApplyRequest> requests = <ComicRefreshApplyRequest>[];

  @override
  Future<ComicRefreshApplyResult> apply(
    ComicRefreshApplyRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}

class _FakeComicRepository implements ComicRepository {
  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
      title: 'Test Comic',
      sourceTitle: 'Source Test Comic',
      customTitle: 'Custom Test Comic',
      author: 'Author A',
      sourceAuthor: 'Source Author',
      customAuthor: 'Custom Author',
      translationGroup: 'Group A',
      sourceTranslationGroup: 'Source Group',
      customTranslationGroup: 'Custom Group',
      customSearchTitle: 'Search Test Comic',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 2,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    return const <ComicEpisodeItem>[
      ComicEpisodeItem(
        episodeId: 'comic:1:100',
        comicId: 'comic:1',
        episodeTitle: '第1话',
        sourceTid: '100',
        sourceUrl: 'thread-100-1-1.html',
        orderIndex: 0,
        publishTimeText: '2026-01-01',
      ),
      ComicEpisodeItem(
        episodeId: 'comic:1:101',
        comicId: 'comic:1',
        episodeTitle: '第2话',
        sourceTid: '101',
        sourceUrl: 'thread-101-1-1.html',
        orderIndex: 1,
        publishTimeText: '2026-01-02',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
