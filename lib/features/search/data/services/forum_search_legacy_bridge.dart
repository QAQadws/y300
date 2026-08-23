import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';
import 'package:y300/features/search/domain/repositories/forum_search_repository.dart';

/// Compatibility bridge for existing test hosts and non-migrated callers.
/// Production pages use [forumSearchCoordinatorProvider] directly.
final class LegacyForumSearchCoordinatorAdapter
    implements ForumSearchCoordinator, ForumSearchReadQueueStateReader {
  LegacyForumSearchCoordinatorAdapter(this._legacy) {
    final queue = _legacy;
    if (queue is ForumSearchQueueStateReader) {
      final value = (queue as ForumSearchQueueStateReader).snapshot.value;
      _snapshot.value = ForumSearchReadSchedulerSnapshot(
        pendingCount: value.pendingCount,
        running: value.running,
        headKeyword: value.headKeyword,
        estimatedWait: value.estimatedWait,
      );
    }
  }

  final ForumSearchService _legacy;
  final Map<String, String> _continuations = <String, String>{};
  final Map<String, ForumSearchPageIdentity> _continuationByUrl =
      <String, ForumSearchPageIdentity>{};
  final ValueNotifier<ForumSearchReadSchedulerSnapshot> _snapshot =
      ValueNotifier<ForumSearchReadSchedulerSnapshot>(
        ForumSearchReadSchedulerSnapshot.empty,
      );
  int _nextToken = 0;

  @override
  ValueListenable<ForumSearchReadSchedulerSnapshot> get snapshot => _snapshot;

  @override
  Future<ForumSearchExecution> search(
    ForumSearchQuery query, {
    bool enforceRateLimit = true,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    try {
      final result = await _legacy.searchForum(
        keyword: query.normalizedKeyword,
        context: _legacyContext(query),
        enforceRateLimit: enforceRateLimit,
      );
      if (result.rateLimited) {
        return ForumSearchExecution.rateLimited(result.retryAfter);
      }
      return ForumSearchExecution.read(
        _toReadResult(query, result, currentPage: 1),
      );
    } catch (_) {
      return const ForumSearchExecution.read(
        DataReadFailure(
          kind: DataReadFailureKind.unknown,
          code: 'forum_search_legacy_failure',
          diagnosticMessage: 'Forum search failed.',
        ),
      );
    }
  }

  @override
  Future<ForumSearchExecution> loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page,
  ) async {
    final nextPageUrl = _continuations[page.token];
    if (nextPageUrl == null) {
      return const ForumSearchExecution.read(
        DataReadFailure(
          kind: DataReadFailureKind.business,
          code: 'forum_search_legacy_continuation_invalid',
          diagnosticMessage: 'Forum search continuation is invalid.',
        ),
      );
    }
    try {
      final result = await _legacy.fetchNextPage(
        nextPageUrl: nextPageUrl,
        context: _legacyContext(query),
      );
      return ForumSearchExecution.read(
        _toReadResult(query, result, currentPage: page.page),
      );
    } catch (_) {
      return const ForumSearchExecution.read(
        DataReadFailure(
          kind: DataReadFailureKind.unknown,
          code: 'forum_search_legacy_failure',
          diagnosticMessage: 'Forum search failed.',
        ),
      );
    }
  }

  DataReadResult<ForumSearchData, ForumSearchReadCapabilities> _toReadResult(
    ForumSearchQuery query,
    DiscuzSearchResponse response, {
    required int currentPage,
  }) {
    final nextUrl = response.nextPageUrl?.trim();
    ForumSearchPageIdentity? nextPage;
    if (nextUrl != null && nextUrl.isNotEmpty) {
      nextPage = _continuationByUrl[nextUrl];
      if (nextPage == null) {
        final token = 'legacy-search-${_nextToken++}';
        nextPage = ForumSearchPageIdentity(
          token: token,
          page: _pageFromUrl(nextUrl, fallback: currentPage + 1),
        );
        _continuations[token] = nextUrl;
        _continuationByUrl[nextUrl] = nextPage;
      }
    }
    final data = ForumSearchData(
      query: query.normalized(),
      topics: List<ForumSearchTopicSummary>.unmodifiable(
        response.items.map(
          (item) => ForumSearchTopicSummary(
            tid: item.tid,
            title: item.title,
            forumId: item.fid.trim().isEmpty ? null : item.fid,
            authorName: item.author,
            publishedAtText: item.timeText,
          ),
        ),
      ),
      pagination: ForumSearchPagination(
        currentPage: currentPage,
        nextPage: nextPage,
        precision: nextPage == null
            ? PaginationPrecision.unknown
            : PaginationPrecision.directional,
      ),
    );
    final values =
        DataCapabilitySet<ForumSearchCapability>.from(
              supported: const <ForumSearchCapability>[
                ForumSearchCapability.stableTopicIdentity,
                ForumSearchCapability.orderedTopics,
                ForumSearchCapability.topicTitle,
              ],
            )
            .withSupport(
              ForumSearchCapability.topicForum,
              data.topics.any((topic) => topic.forumId != null)
                  ? DataCapabilitySupport.supported
                  : DataCapabilitySupport.unsupported,
            )
            .withSupport(
              ForumSearchCapability.topicAuthor,
              data.topics.any((topic) => topic.authorName != null)
                  ? DataCapabilitySupport.supported
                  : DataCapabilitySupport.unsupported,
            )
            .withSupport(
              ForumSearchCapability.topicPublishedAt,
              data.topics.any((topic) => topic.publishedAtText != null)
                  ? DataCapabilitySupport.supported
                  : DataCapabilitySupport.unsupported,
            )
            .withSupport(
              ForumSearchCapability.directionalPagination,
              nextPage == null
                  ? DataCapabilitySupport.unsupported
                  : DataCapabilitySupport.supported,
            )
            .withSupport(
              ForumSearchCapability.searchContinuation,
              nextPage == null
                  ? DataCapabilitySupport.unsupported
                  : DataCapabilitySupport.supported,
            );
    return DataReadSuccess(
      data: data,
      capabilities: ForumSearchReadCapabilities(
        values: values,
        paginationPrecision: data.pagination.precision,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }

  DiscuzSearchContext _legacyContext(ForumSearchQuery query) {
    return query.scope == ForumSearchScope.currentForum
        ? DiscuzSearchContext.curForum(srhfid: query.normalizedForumId ?? '')
        : const DiscuzSearchContext.forum();
  }

  int _pageFromUrl(String value, {required int fallback}) {
    final page = int.tryParse(
      Uri.tryParse(value)?.queryParameters['page'] ?? '',
    );
    return page == null || page < 1 ? fallback : page;
  }
}

final forumSearchPageCoordinatorProvider = Provider<ForumSearchCoordinator>((
  ref,
) {
  final legacy = ref.watch(discuzSearchServiceProvider);
  if (legacy is DefaultForumSearchServiceMarker) {
    return ref.watch(forumSearchCoordinatorProvider);
  }
  return LegacyForumSearchCoordinatorAdapter(legacy);
});
