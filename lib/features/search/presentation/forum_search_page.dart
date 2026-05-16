import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/search/data/forum_search_scheduler.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

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
  String? _hint;
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
    final waitingMessage = _searchWaitingMessage(service);
    if (waitingMessage != null) {
      setState(() {
        _hint = waitingMessage;
      });
      return;
    }
    setState(() {
      _loading = true;
      _hint = null;
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
          final seconds = result.retryAfter.inSeconds <= 0 ? 1 : result.retryAfter.inSeconds;
          _hint = '请 $seconds 秒后重试';
          _items = const <DiscuzSearchResultItem>[];
          _nextPageUrl = null;
        } else {
          _hint = result.items.isEmpty ? '未找到结果' : null;
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
        _hint = '搜索失败：$error';
        _items = const <DiscuzSearchResultItem>[];
        _nextPageUrl = null;
      });
    }
  }

  String? _searchWaitingMessage(ForumSearchService service) {
    final comicQueue = ref.read(comicSearchRefreshQueueSnapshotProvider).value;
    final comicQueueMessage = _comicQueueWaitingMessage(comicQueue);
    if (comicQueueMessage != null) {
      return comicQueueMessage;
    }
    final Object serviceObject = service;
    if (serviceObject is! ForumSearchQueueStateReader) {
      return null;
    }
    return _schedulerWaitingMessage(serviceObject.snapshot.value);
  }

  String? _comicQueueWaitingMessage(ComicSearchRefreshQueueSnapshot snapshot) {
    if (!snapshot.active) {
      return null;
    }
    final message = snapshot.waitingMessage?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return '正在等待搜索 预计耗时${_formatSeconds(snapshot.estimatedDuration)}s';
  }

  String? _schedulerWaitingMessage(ForumSearchSchedulerSnapshot snapshot) {
    if (!snapshot.active) {
      return null;
    }
    final keyword = snapshot.headKeyword?.trim();
    final title = keyword == null || keyword.isEmpty ? '论坛搜索' : keyword;
    return '$title 正在等待搜索 预计耗时${_formatSeconds(snapshot.estimatedWait)}s';
  }

  String _formatSeconds(Duration duration) {
    final tenths = (duration.inMilliseconds / 100).round();
    if (tenths % 10 == 0) {
      return '${tenths ~/ 10}';
    }
    return (tenths / 10).toStringAsFixed(1);
  }

  Future<void> _loadMore() async {
    final nextPageUrl = _nextPageUrl;
    if (_loading || _loadingMore || nextPageUrl == null || nextPageUrl.trim().isEmpty) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _hint = null;
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
        _hint = '加载更多失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
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
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入关键词',
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_hint!, key: const Key('forum-search-hint')),
              ),
            ),
          Expanded(
            child: ListView(
              key: const Key('forum-search-result-list'),
              children: [
                for (final item in _items) ...[
                  ListTile(
                    title: Text(item.title),
                    subtitle: Text('Tid: ${item.tid}'),
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
                      child: const Text('查看更多'),
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
