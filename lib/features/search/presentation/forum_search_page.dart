import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/search_text_resolver.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumSearchPage extends ConsumerStatefulWidget {
  const ForumSearchPage({
    super.key,
    this.context = const DiscuzSearchContext.forum(),
  });

  final DiscuzSearchContext context;

  @override
  ConsumerState<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends ConsumerState<ForumSearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  bool _loadingMore = false;
  SearchNotice? _notice;
  String? _nextPageUrl;
  List<DiscuzSearchResultItem> _items = const <DiscuzSearchResultItem>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || _loading) {
      return;
    }
    final service = ref.read(discuzSearchServiceProvider);
    final waitingNotice = _searchWaitingNotice(service);
    if (waitingNotice != null) {
      setState(() {
        _notice = waitingNotice;
      });
      return;
    }
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      final result = await service.searchForum(
        keyword: keyword,
        context: widget.context,
        enforceRateLimit: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        if (result.rateLimited) {
          final seconds = result.retryAfter.inSeconds <= 0
              ? 1
              : result.retryAfter.inSeconds;
          _notice = SearchRateLimitedNotice(seconds);
          _items = const <DiscuzSearchResultItem>[];
          _nextPageUrl = null;
        } else {
          _notice = result.items.isEmpty ? const SearchNoResultsNotice() : null;
          _items = result.items;
          _nextPageUrl = result.nextPageUrl;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _notice = SearchFailedNotice(error);
        _items = const <DiscuzSearchResultItem>[];
        _nextPageUrl = null;
      });
    }
  }

  SearchNotice? _searchWaitingNotice(ForumSearchService service) {
    final comicQueue = ref.read(comicSearchRefreshQueueSnapshotProvider).value;
    final comicQueueNotice = _comicQueueWaitingNotice(comicQueue);
    if (comicQueueNotice != null) {
      return comicQueueNotice;
    }
    final Object serviceObject = service;
    if (serviceObject is! ForumSearchQueueStateReader) {
      return null;
    }
    return _schedulerWaitingNotice(serviceObject.snapshot.value);
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

  SearchNotice? _schedulerWaitingNotice(ForumSearchSchedulerSnapshot snapshot) {
    if (!snapshot.active) {
      return null;
    }
    return SearchQueueWaitingNotice(
      subject: snapshot.headKeyword,
      estimatedWait: snapshot.estimatedWait,
    );
  }

  Future<void> _loadMore() async {
    final nextPageUrl = _nextPageUrl;
    if (_loading ||
        _loadingMore ||
        nextPageUrl == null ||
        nextPageUrl.trim().isEmpty) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _notice = null;
    });
    try {
      final service = ref.read(discuzSearchServiceProvider);
      final result = await service.fetchNextPage(
        nextPageUrl: nextPageUrl,
        context: widget.context,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _items = <DiscuzSearchResultItem>[..._items, ...result.items];
        _nextPageUrl = result.nextPageUrl;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _notice = SearchLoadMoreFailedNotice(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchTitle),
        actions: [
          IconButton(
            key: const Key('forum-search-submit-button'),
            onPressed: _search,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('forum-search-input'),
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.searchInputHint,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  SearchTextResolver.notice(l10n, _notice!),
                  key: const Key('forum-search-hint'),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              key: const Key('forum-search-result-list'),
              children: [
                for (final item in _items) ...[
                  ListTile(
                    title: Text(item.title),
                    subtitle: Text(l10n.searchResultTid(item.tid)),
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
                  ),
                  const Divider(height: 1),
                ],
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_loadingMore && (_nextPageUrl?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton(
                      key: const Key('forum-search-load-more-button'),
                      onPressed: _loadMore,
                      child: Text(l10n.searchLoadMore),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
