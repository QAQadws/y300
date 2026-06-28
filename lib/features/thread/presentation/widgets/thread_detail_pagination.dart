part of 'thread_detail_widgets.dart';

// Pagination widgets for thread detail: load-more row, page buttons, and the
// page-picker dialog. Moved verbatim from thread_detail_widgets.dart (Phase 5b
// file split); keys and logic unchanged.

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
            label: '上一页',
            palette: palette,
          ),
          const SizedBox(width: 6),
          _ThreadPageButton(
            key: const Key('thread-detail-current-page-button'),
            onPressed: () => _showPagePicker(context),
            label: '第 $currentPage 页',
            palette: palette,
          ),
          const SizedBox(width: 6),
          _ThreadPageButton(
            key: const Key('thread-detail-load-more-button'),
            onPressed: hasMore ? onLoadNextPage : null,
            label: hasMore ? '下一页' : '没有更多',
            palette: palette,
          ),
        ],
      ),
    );
  }

  Future<void> _showPagePicker(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _ThreadDetailPagePickerDialog(
        currentPage: currentPage,
        lastPage: lastPage,
      ),
    );
    if (selected == null || selected == currentPage) {
      return;
    }
    onLoadPageNumber(selected);
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
        style: TextButton.styleFrom(
          backgroundColor: palette.chipBackground,
          disabledBackgroundColor: palette.chipBackground,
          foregroundColor: palette.muted,
          disabledForegroundColor: palette.softText,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ThreadDetailPagePickerDialog extends StatefulWidget {
  const _ThreadDetailPagePickerDialog({
    required this.currentPage,
    required this.lastPage,
  });

  final int currentPage;
  final int? lastPage;

  @override
  State<_ThreadDetailPagePickerDialog> createState() =>
      _ThreadDetailPagePickerDialogState();
}

class _ThreadDetailPagePickerDialogState
    extends State<_ThreadDetailPagePickerDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = widget.lastPage;
    return AlertDialog(
      key: const Key('thread-detail-page-picker-dialog'),
      title: const Text('选择页码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('thread-detail-page-input'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: lastPage == null ? '页码' : '页码（1-$lastPage）',
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-5-button'),
                increment: 5,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-10-button'),
                increment: 10,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _PageIncrementButton(
                buttonKey: const Key('thread-detail-page-plus-50-button'),
                increment: 50,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('thread-detail-page-confirm-button'),
          onPressed: () => _submit(context),
          child: const Text('跳转'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final page = int.tryParse(_controller.text.trim());
    final lastPage = widget.lastPage;
    if (page == null || page < 1) {
      setState(() => _errorText = '请输入有效页码');
      return;
    }
    if (lastPage != null && page > lastPage) {
      setState(() => _errorText = '不能超过第$lastPage页');
      return;
    }
    Navigator.of(context).pop(page);
  }
}

class _PageIncrementButton extends StatelessWidget {
  const _PageIncrementButton({
    required this.buttonKey,
    required this.increment,
    required this.currentPage,
    required this.lastPage,
  });

  final Key buttonKey;
  final int increment;
  final int currentPage;
  final int? lastPage;

  @override
  Widget build(BuildContext context) {
    final targetPage = currentPage + increment;
    final maxPage = lastPage;
    final enabled = maxPage == null || targetPage <= maxPage;
    return OutlinedButton(
      key: buttonKey,
      onPressed: enabled ? () => Navigator.of(context).pop(targetPage) : null,
      child: Text('+$increment'),
    );
  }
}
