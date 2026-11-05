import 'package:flutter/material.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/l10n/app_localizations.dart';

class NovelReaderPositionBookmarksDialog extends StatefulWidget {
  const NovelReaderPositionBookmarksDialog({
    super.key,
    required this.bookmarks,
    required this.isLoading,
    required this.onSave,
    required this.onRemove,
  });

  final List<NovelReaderBookmark> bookmarks;
  final bool isLoading;
  final Future<void> Function()? onSave;
  final Future<void> Function(NovelReaderBookmark) onRemove;

  @override
  State<NovelReaderPositionBookmarksDialog> createState() =>
      _NovelReaderPositionBookmarksDialogState();
}

class _NovelReaderPositionBookmarksDialogState
    extends State<NovelReaderPositionBookmarksDialog> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    var failed = false;
    try {
      await action();
    } on Object {
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final save = widget.onSave;
    final bookmarks = widget.bookmarks;
    return AlertDialog(
      title: Text(l10n.novelPositionBookmarks),
      content: SizedBox(
        width: 440,
        height: 340,
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_failed) Text(l10n.novelBookmarkOperationFailed),
            Expanded(
              child: bookmarks.isEmpty
                  ? Center(
                      child: widget.isLoading
                          ? const CircularProgressIndicator()
                          : Text(l10n.novelNoPositionBookmarks),
                    )
                  : ListView.builder(
                      itemCount: bookmarks.length,
                      itemBuilder: (context, index) {
                        final bookmark =
                            bookmarks[bookmarks.length - index - 1];
                        return ListTile(
                          key: ValueKey(bookmark.bookmarkId),
                          enabled: !_busy,
                          title: Text(
                            bookmark.title.isEmpty
                                ? l10n.novelBookmark
                                : bookmark.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: bookmark.snippet.isEmpty
                              ? null
                              : Text(
                                  bookmark.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, bookmark),
                          trailing: IconButton(
                            tooltip: l10n.commonRemove,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy
                                ? null
                                : () =>
                                      _mutate(() => widget.onRemove(bookmark)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
        FilledButton.tonal(
          onPressed: _busy || save == null ? null : () => _mutate(save),
          child: Text(l10n.novelSavePositionBookmark),
        ),
      ],
    );
  }
}
