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
    required this.palette,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final int currentPage;
  final int? lastPage;
  final bool canLoadPrevious;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onLoadPageNumber;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ThreadPageButton(
            key: const Key('thread-detail-previous-page-button'),
            onPressed: canLoadPrevious ? onLoadPreviousPage : null,
            label: l10n.threadDetailPreviousPage,
            palette: palette,
          ),
          const SizedBox(width: 6),
          NativePageDropdownButton(
            buttonKey: const Key('thread-detail-current-page-button'),
            menuKeyPrefix: 'thread-detail',
            currentPage: currentPage,
            lastPage: lastPage,
            hasMore: hasMore,
            enabled: true,
            label: l10n.threadDetailPage(currentPage),
            style: _threadPageButtonStyle(context, palette),
            onSelected: onLoadPageNumber,
          ),
          const SizedBox(width: 6),
          _ThreadPageButton(
            key: const Key('thread-detail-load-more-button'),
            onPressed: hasMore ? onLoadNextPage : null,
            label: hasMore
                ? l10n.threadDetailNextPage
                : l10n.threadDetailNoMore,
            palette: palette,
          ),
        ],
      ),
    );
  }
}

class _ThreadPageButton extends StatelessWidget {
  const _ThreadPageButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.palette,
  });

  final VoidCallback? onPressed;
  final String label;
  final ThreadDetailNativePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onPressed,
        style: _threadPageButtonStyle(context, palette),
        child: Text(label),
      ),
    );
  }
}

ButtonStyle _threadPageButtonStyle(
  BuildContext context,
  ThreadDetailNativePalette palette,
) {
  return TextButton.styleFrom(
    backgroundColor: palette.chipBackground,
    disabledBackgroundColor: palette.chipBackground,
    foregroundColor: palette.muted,
    disabledForegroundColor: palette.softText,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    minimumSize: const Size(0, 34),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}
