part of 'thread_detail_widgets.dart';

// Pagination widgets for thread detail: load-more row and page controls.

class ThreadLoadMoreSection extends StatelessWidget {
  const ThreadLoadMoreSection({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.currentPage,
    required this.lastPage,
    required this.canLoadPrevious,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onLoadPageNumber,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final int currentPage;
  final int? lastPage;
  final bool canLoadPrevious;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onLoadPageNumber;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return NativePaginationBar(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      spacing: 6,
      currentPage: currentPage,
      lastPage: lastPage,
      hasMore: hasMore,
      canLoadPrevious: canLoadPrevious,
      isLoading: isLoadingMore,
      onLoadPrevious: onLoadPreviousPage,
      onLoadNext: onLoadNextPage,
      onSelectPage: onLoadPageNumber,
      previousLabel: l10n.threadDetailPreviousPage,
      currentLabel: l10n.threadDetailPage(currentPage),
      nextLabel: hasMore ? l10n.threadDetailNextPage : l10n.threadDetailNoMore,
      previousButtonKey: const Key('thread-detail-previous-page-button'),
      currentPageButtonKey: const Key('thread-detail-current-page-button'),
      nextButtonKey: const Key('thread-detail-load-more-button'),
      menuKeyPrefix: 'thread-detail',
    );
  }
}
