import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';
import 'package:y300/features/search/presentation/search_text_resolver.dart';
import 'package:y300/features/search/presentation/widgets/forum_search_result_card.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/inline_search_app_bar.dart';

class ForumSearchPage extends ConsumerStatefulWidget {
  const ForumSearchPage({
    super.key,
    this.scope = ForumSearchScope.allForums,
    this.forumId,
  });

  final ForumSearchScope scope;
  final String? forumId;

  @override
  ConsumerState<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends ConsumerState<ForumSearchPage> {
  static const double _autoLoadMoreThreshold = 240;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  bool _loadingMore = false;
  SearchNotice? _notice;
  SearchNotice? _loadMoreNotice;
  ForumSearchData? _data;
  ForumSearchReadCapabilities? _capabilities;
  DataReadMetadata? _metadata;
  final Set<ForumSearchPageIdentity> _requestedPages =
      <ForumSearchPageIdentity>{};
  int _queryRevision = 0;

  List<ForumSearchTopicSummary> get _items =>
      _data?.topics ?? const <ForumSearchTopicSummary>[];

  ForumSearchPageIdentity? get _nextPage => _data?.pagination.nextPage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _queryRevision += 1;
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || _loading) {
      return;
    }
    final query = _buildQuery(keyword);
    final previous = _data;
    final refreshing = previous != null && _sameQuery(previous.query, query);
    final coordinator = ref.read(forumSearchCoordinatorProvider);
    final waitingNotice = _searchWaitingNotice(coordinator);
    if (waitingNotice != null) {
      setState(() => _notice = waitingNotice);
      return;
    }
    final revision = ++_queryRevision;
    _requestedPages.clear();
    setState(() {
      _loading = true;
      _loadingMore = false;
      _notice = null;
      _loadMoreNotice = null;
      if (!refreshing) {
        _data = null;
        _capabilities = null;
        _metadata = null;
      }
    });
    final execution = await coordinator.search(
      query,
      enforceRateLimit: true,
      cachePolicy: refreshing
          ? CacheLoadPolicy.networkFirst
          : CacheLoadPolicy.cacheFirst,
    );
    if (!mounted || revision != _queryRevision) {
      return;
    }
    setState(() {
      _loading = false;
      if (execution.isRateLimited) {
        final seconds = execution.retryAfter!.inSeconds <= 0
            ? 1
            : execution.retryAfter!.inSeconds;
        _notice = SearchRateLimitedNotice(seconds);
        if (!refreshing) {
          _data = null;
          _capabilities = null;
          _metadata = null;
        }
        return;
      }
      final result = execution.readResult!;
      result.when(
        success: (data, capabilities, metadata) {
          _data = data;
          _capabilities = capabilities;
          _metadata = metadata;
          _notice = data.topics.isEmpty ? const SearchNoResultsNotice() : null;
        },
        failure: (failure) {
          _notice = SearchFailedNotice(failure);
          if (!refreshing) {
            _data = null;
            _capabilities = null;
            _metadata = null;
          }
        },
      );
    });
    _scheduleAutoLoadMoreCheck(revision);
  }

  ForumSearchQuery _buildQuery(String keyword) {
    return ForumSearchQuery(
      keyword: keyword,
      scope: widget.scope,
      forumId: widget.forumId,
    );
  }

  bool _sameQuery(ForumSearchQuery left, ForumSearchQuery right) {
    return left.normalizedKeyword == right.normalizedKeyword &&
        left.scope == right.scope &&
        left.normalizedForumId == right.normalizedForumId;
  }

  SearchNotice? _searchWaitingNotice(ForumSearchCoordinator coordinator) {
    final comicQueue = ref.read(comicSearchRefreshQueueSnapshotProvider).value;
    final comicQueueNotice = _comicQueueWaitingNotice(comicQueue);
    if (comicQueueNotice != null) {
      return comicQueueNotice;
    }
    if (coordinator is! ForumSearchReadQueueStateReader) {
      return null;
    }
    return _schedulerWaitingNotice(
      (coordinator as ForumSearchReadQueueStateReader).snapshot.value,
    );
  }

  SearchNotice? _comicQueueWaitingNotice(
    ComicSearchRefreshQueueSnapshot snapshot,
  ) {
    if (!snapshot.active) {
      return null;
    }
    return SearchLibraryTaskNotice(
      LibraryShelfTaskProgress(
        code: LibraryShelfTaskProgressCode.comicSearchWaiting,
        subject: snapshot.headTitle,
        estimatedDuration: snapshot.estimatedDuration,
        total: snapshot.totalCount,
      ),
    );
  }

  SearchNotice? _schedulerWaitingNotice(
    ForumSearchReadSchedulerSnapshot snapshot,
  ) {
    if (!snapshot.active) {
      return null;
    }
    return SearchQueueWaitingNotice(
      subject: snapshot.headKeyword,
      estimatedWait: snapshot.estimatedWait,
    );
  }

  Future<void> _loadMore({bool automatic = false}) async {
    final nextPage = _nextPage;
    if (_loading || _loadingMore || nextPage == null) {
      return;
    }
    if (automatic && _requestedPages.contains(nextPage)) {
      return;
    }
    _requestedPages.add(nextPage);
    final revision = _queryRevision;
    setState(() {
      _loadingMore = true;
      _loadMoreNotice = null;
    });
    final coordinator = ref.read(forumSearchCoordinatorProvider);
    final execution = await coordinator.loadNextPage(
      _buildQuery(_controller.text),
      nextPage,
    );
    if (!mounted || revision != _queryRevision) {
      return;
    }
    setState(() {
      _loadingMore = false;
      if (execution.isRateLimited) {
        _loadMoreNotice = SearchLoadMoreFailedNotice(execution.retryAfter!);
        return;
      }
      final result = execution.readResult!;
      result.when(
        success: (data, capabilities, metadata) {
          final existingIds = _items.map((item) => item.tid).toSet();
          if (data.topics.any((item) => existingIds.contains(item.tid))) {
            _loadMoreNotice = const SearchLoadMoreFailedNotice(
              DataReadFailure<ForumSearchData, ForumSearchReadCapabilities>(
                kind: DataReadFailureKind.parse,
                code: 'forum_search_duplicate_topic_identity',
                diagnosticMessage: 'Forum search topic identity is duplicated.',
              ),
            );
            return;
          }
          final previous = _data!;
          _data = ForumSearchData(
            query: previous.query,
            topics: <ForumSearchTopicSummary>[
              ...previous.topics,
              ...data.topics,
            ],
            pagination: data.pagination,
          );
          _capabilities = _capabilities!.intersect(capabilities);
          _metadata = _metadata!.merge(metadata);
        },
        failure: (failure) {
          _loadMoreNotice = SearchLoadMoreFailedNotice(failure);
        },
      );
    });
    _scheduleAutoLoadMoreCheck(revision);
  }

  void _handleScroll() => _tryAutoLoadMore();

  void _tryAutoLoadMore({int? revision}) {
    if ((revision != null && revision != _queryRevision) ||
        !_scrollController.hasClients ||
        _nextPage == null) {
      return;
    }
    if (_scrollController.position.extentAfter > _autoLoadMoreThreshold) {
      return;
    }
    unawaited(_loadMore(automatic: true));
  }

  void _scheduleAutoLoadMoreCheck(int revision) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _queryRevision) {
        return;
      }
      _tryAutoLoadMore(revision: revision);
    });
  }

  void _handleQueryChanged(String value) {
    _queryRevision += 1;
    _requestedPages.clear();
    if (!_loading &&
        !_loadingMore &&
        _notice == null &&
        _loadMoreNotice == null) {
      return;
    }
    setState(() {
      _loading = false;
      _loadingMore = false;
      _notice = null;
      _loadMoreNotice = null;
      _data = null;
      _capabilities = null;
      _metadata = null;
    });
  }

  void _clearSearch() {
    _queryRevision += 1;
    _requestedPages.clear();
    setState(() {
      _loading = false;
      _loadingMore = false;
      _notice = null;
      _loadMoreNotice = null;
      _data = null;
      _capabilities = null;
      _metadata = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    return Scaffold(
      backgroundColor: palette.background,
      appBar: InlineSearchAppBar(
        controller: _controller,
        focusNode: _focusNode,
        fieldKey: const Key('forum-search-input'),
        backButtonKey: const Key('forum-search-back-button'),
        clearButtonKey: const Key('forum-search-clear-button'),
        submitButtonKey: const Key('forum-search-submit-button'),
        hintText: l10n.searchInputHint,
        clearTooltip: l10n.commonClear,
        submitTooltip: l10n.commonSearch,
        submitEnabled: !_loading,
        onBack: () => Navigator.of(context).maybePop(),
        onChanged: _handleQueryChanged,
        onCleared: _clearSearch,
        onSubmitted: (_) => _search(),
        onSubmit: _search,
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Material(
                color: palette.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    SearchTextResolver.notice(l10n, _notice!),
                    key: const Key('forum-search-hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.bodyText,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              key: const Key('forum-search-result-list'),
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
              itemCount:
                  _items.length +
                  ((_loadingMore || _loadMoreNotice != null) ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  if (_loadingMore) {
                    return const Padding(
                      key: Key('forum-search-load-more-progress'),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    );
                  }
                  return Material(
                    key: const Key('forum-search-load-more-error'),
                    color: palette.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
                      child: Column(
                        children: [
                          Text(
                            SearchTextResolver.notice(l10n, _loadMoreNotice!),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.bodyText,
                                  height: 1.35,
                                ),
                          ),
                          const SizedBox(height: 2),
                          TextButton(
                            key: const Key('forum-search-load-more-button'),
                            onPressed: () => unawaited(_loadMore()),
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final item = _items[index];
                return ForumSearchResultCard(
                  key: Key('forum-search-result-${item.tid}'),
                  item: item,
                  capabilities: _capabilities,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ThreadDetailPage(
                          tid: item.tid,
                          subject: item.title,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
