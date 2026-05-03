import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class ForumSearchPage extends ConsumerStatefulWidget {
  const ForumSearchPage({
    super.key,
    this.srhfid = '30',
  });

  final String srhfid;

  @override
  ConsumerState<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends ConsumerState<ForumSearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _hint;
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
    setState(() {
      _loading = true;
      _hint = null;
    });
    try {
      final service = ref.read(discuzSearchServiceProvider);
      final result = await service.searchForum(
        keyword: keyword,
        srhfid: widget.srhfid,
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
        } else {
          _hint = result.items.isEmpty ? '未找到结果' : null;
          _items = result.items;
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
                hintText: '输入关键词（仅搜索漫画区）',
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
            child: ListView.separated(
              key: const Key('forum-search-result-list'),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
