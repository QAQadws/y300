import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_date_grouping_policy.dart';
import 'package:y300/features/history/presentation/controllers/history_controller.dart';
import 'package:y300/features/history/presentation/models/history_view_state.dart';
import 'package:y300/features/history/presentation/widgets/history_day_section.dart';
import 'package:y300/features/history/presentation/widgets/history_entry_tile.dart';

typedef HistoryEntryOpenCallback =
    Future<HistoryOpenResult> Function(
      BuildContext context,
      HistoryEntry entry,
    );

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({
    super.key,
    required this.onOpenEntry,
    this.controller,
    this.clock,
    this.groupingPolicy = const HistoryDateGroupingPolicy(),
    this.imageHeaderBuilder,
    this.thumbnailBuilder,
  });

  final HistoryEntryOpenCallback onOpenEntry;
  final HistoryController? controller;
  final HistoryClock? clock;
  final HistoryDateGroupingPolicy groupingPolicy;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final HistoryThumbnailBuilder? thumbnailBuilder;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late HistoryController _controller;
  late HistoryClock _clock;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchActive = false;
  double _timelineOffset = 0;

  @override
  void initState() {
    super.initState();
    _bindController(widget.controller ?? ref.read(historyControllerProvider));
    _clock = widget.clock ?? ref.read(historyClockProvider);
    _scrollController.addListener(_handleScroll);
    unawaited(_controller.initialize());
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final HistoryController nextController =
        widget.controller ?? ref.read(historyControllerProvider);
    if (!identical(nextController, _controller)) {
      _controller.removeListener(_handleControllerChanged);
      _bindController(nextController);
      unawaited(_controller.initialize());
    }
    if (!identical(oldWidget.clock, widget.clock)) {
      _clock = widget.clock ?? ref.read(historyClockProvider);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _bindController(HistoryController controller) {
    _controller = controller..addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 240) {
      unawaited(_controller.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null) {
      ref.watch(historyControllerProvider);
    }
    final state = _controller.state;
    return PopScope<void>(
      canPop: !_searchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchActive) {
          unawaited(_closeSearch());
        }
      },
      child: Scaffold(
        key: const Key('history-page'),
        appBar: _buildAppBar(state),
        body: _buildBody(state),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(HistoryViewState state) {
    if (_searchActive) {
      return AppBar(
        leading: IconButton(
          key: const Key('history-search-close'),
          tooltip: '退出搜索',
          onPressed: _closeSearch,
          icon: const Icon(Icons.arrow_back),
        ),
        title: TextField(
          key: const Key('history-search-input'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索记录',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('history-search-clear'),
                    tooltip: '清除搜索',
                    onPressed: () {
                      _searchController.clear();
                      _controller.updateSearchText('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (value) {
            _controller.updateSearchText(value);
            setState(() {});
          },
        ),
      );
    }
    return AppBar(
      title: const Text('记录'),
      actions: [
        IconButton(
          key: const Key('history-search-button'),
          tooltip: '搜索记录',
          onPressed: _openSearch,
          icon: const Icon(Icons.search),
        ),
        if (state.items.isNotEmpty)
          IconButton(
            key: const Key('history-clear-all-button'),
            tooltip: '清空记录',
            onPressed: _confirmClearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
      ],
    );
  }

  Widget _buildBody(HistoryViewState state) {
    if (state.isInitialLoading && state.items.isEmpty) {
      return const Center(
        key: Key('history-initial-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return _HistoryErrorState(
        message: state.errorMessage!,
        onRetry: () => _controller.refresh(showLoading: true),
      );
    }
    if (state.items.isEmpty) {
      return _HistoryEmptyState(searching: state.isSearching);
    }

    final groups = widget.groupingPolicy.group(state.items, now: _clock.now());
    return CustomScrollView(
      key: const PageStorageKey<String>('history-timeline-scroll'),
      controller: _scrollController,
      slivers: [
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: HistoryDaySectionHeader(label: group.label),
          ),
          SliverList.builder(
            itemCount: group.entries.length,
            itemBuilder: (context, index) {
              final entry = group.entries[index];
              return HistoryEntryTile(
                key: ValueKey<String>('history-entry-${entry.target}'),
                entry: entry,
                headerBuilder: widget.imageHeaderBuilder,
                thumbnailBuilder: widget.thumbnailBuilder,
                onOpen: () => _openEntry(entry),
                onDelete: () => _deleteEntry(entry),
              );
            },
          ),
        ],
        if (state.isLoadingMore)
          const SliverToBoxAdapter(
            child: SizedBox(
              key: Key('history-load-more-progress'),
              height: 64,
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (state.loadMoreError != null)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton.icon(
                key: const Key('history-load-more-retry'),
                onPressed: _controller.loadMore,
                icon: const Icon(Icons.refresh),
                label: const Text('加载失败，点击重试'),
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _openSearch() {
    if (_scrollController.hasClients) {
      _timelineOffset = _scrollController.offset;
    }
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _closeSearch() async {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() => _searchActive = false);
    await _controller.clearSearch();
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(
      _timelineOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
    );
  }

  Future<void> _openEntry(HistoryEntry entry) async {
    final result = await widget.onOpenEntry(context, entry);
    if (!mounted) {
      return;
    }
    switch (result) {
      case HistoryOpenSuccess():
        return;
      case HistoryOpenUnavailable(:final message):
        _showMessage(message);
      case HistoryOpenFailure():
        _showMessage('打开失败，请稍后重试');
    }
  }

  Future<void> _deleteEntry(HistoryEntry entry) async {
    try {
      await _controller.deleteEntry(entry);
    } catch (_) {
      if (mounted) {
        _showMessage('删除记录失败');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已删除记录'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              unawaited(_restoreEntry(entry));
            },
          ),
        ),
      );
  }

  Future<void> _restoreEntry(HistoryEntry entry) async {
    try {
      await _controller.restoreEntry(entry);
    } catch (_) {
      if (mounted) {
        _showMessage('恢复记录失败');
      }
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空全部记录'),
          content: const Text('浏览记录将被清空，但不会删除收藏、书架作品或下载内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _controller.clearAll();
    } catch (_) {
      if (mounted) {
        _showMessage('清空记录失败');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: Key(searching ? 'history-search-empty' : 'history-empty'),
      child: Text(searching ? '没有搜索结果' : '还没有浏览记录'),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('history-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('记录加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('history-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
