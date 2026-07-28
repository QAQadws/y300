import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_date_grouping_policy.dart';
import 'package:y300/features/history/presentation/controllers/history_controller.dart';
import 'package:y300/features/history/presentation/history_text_resolver.dart';
import 'package:y300/features/history/presentation/models/history_view_state.dart';
import 'package:y300/features/history/presentation/widgets/history_day_section.dart';
import 'package:y300/features/history/presentation/widgets/history_entry_tile.dart';
import 'package:y300/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    if (_searchActive) {
      return AppBar(
        leading: IconButton(
          key: const Key('history-search-close'),
          tooltip: l10n.historySearchClose,
          onPressed: _closeSearch,
          icon: const Icon(Icons.arrow_back),
        ),
        title: TextField(
          key: const Key('history-search-input'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.historySearchHint,
            border: InputBorder.none,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('history-search-clear'),
                    tooltip: l10n.historySearchClear,
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
      title: Text(l10n.historyTitle),
      actions: [
        IconButton(
          key: const Key('history-search-button'),
          tooltip: l10n.historySearchOpen,
          onPressed: _openSearch,
          icon: const Icon(Icons.search),
        ),
        if (state.items.isNotEmpty)
          IconButton(
            key: const Key('history-clear-all-button'),
            tooltip: l10n.historyClearAll,
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
            child: HistoryDaySectionHeader(
              dateKey: _dateKey(group.localDate),
              label: HistoryTextResolver.dateGroupLabel(
                AppLocalizations.of(context),
                group,
              ),
            ),
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
                label: Text(AppLocalizations.of(context).historyLoadMoreFailed),
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
    _handleOpenResult(entry, result);
  }

  void _handleOpenResult(HistoryEntry entry, HistoryOpenResult result) {
    final l10n = AppLocalizations.of(context);
    switch (result) {
      case HistoryOpenSuccess():
        return;
      case final HistoryOpenUnavailable unavailable:
        _showUnavailable(entry, unavailable);
      case final HistoryOpenFailure failure:
        final detail = HistoryTextResolver.safeErrorSummary(failure.error);
        _showMessage(
          detail == null
              ? l10n.historyOpenFailed
              : l10n.historyOpenFailedDetail(detail),
        );
    }
  }

  void _showUnavailable(
    HistoryEntry entry,
    HistoryOpenUnavailable unavailable,
  ) {
    final fallbackTid = _normalizeTid(unavailable.fallbackTid);
    final l10n = AppLocalizations.of(context);
    final detail = unavailable.code == HistoryOpenUnavailableCode.legacyMessage
        ? null
        : HistoryTextResolver.safeErrorSummary(unavailable.detail);
    final message = HistoryTextResolver.unavailableMessage(l10n, unavailable);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: detail == null
              ? Text(message)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(message), Text(detail)],
                ),
          action: fallbackTid != null
              ? SnackBarAction(
                  label: l10n.historyOpenSourceThread,
                  onPressed: () {
                    unawaited(_openSourceThread(entry, fallbackTid));
                  },
                )
              : SnackBarAction(
                  label: l10n.historyDelete,
                  onPressed: () {
                    unawaited(_deleteEntry(entry));
                  },
                ),
        ),
      );
  }

  Future<void> _openSourceThread(HistoryEntry source, String tid) async {
    if (!mounted) {
      return;
    }
    final fallback = HistoryEntry(
      target: HistoryTargetKey(type: HistoryTargetType.thread, id: tid),
      title: source.title,
      contextLabel:
          source.forumName ?? AppLocalizations.of(context).historySourceThread,
      forumName: source.forumName,
      lastSurface: HistoryVisitSurface.threadNative,
      firstVisitedAt: source.firstVisitedAt,
      lastVisitedAt: source.lastVisitedAt,
      visitCount: source.visitCount,
    );
    final result = await widget.onOpenEntry(context, fallback);
    if (mounted) {
      _handleOpenResult(source, result);
    }
  }

  String? _normalizeTid(String? value) {
    final normalized = value?.trim();
    if (normalized == null || !RegExp(r'^\d+$').hasMatch(normalized)) {
      return null;
    }
    final parsed = BigInt.tryParse(normalized);
    return parsed != null && parsed > BigInt.zero ? parsed.toString() : null;
  }

  Future<void> _deleteEntry(HistoryEntry entry) async {
    try {
      await _controller.deleteEntry(entry);
    } catch (_) {
      if (mounted) {
        _showMessage(AppLocalizations.of(context).historyDeleteFailed);
      }
      return;
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).historyClearAllTitle),
          content: Text(AppLocalizations.of(context).historyClearAllBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(context).commonClear),
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
        _showMessage(AppLocalizations.of(context).historyClearAllFailed);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: Key(searching ? 'history-search-empty' : 'history-empty'),
      child: Text(searching ? l10n.historyNoResults : l10n.historyEmpty),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('history-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.historyLoadFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
              label: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
