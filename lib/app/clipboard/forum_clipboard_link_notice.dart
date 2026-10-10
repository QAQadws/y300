import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'forum_clipboard_link_policy.dart';

class ForumClipboardLinkNotice extends StatelessWidget {
  const ForumClipboardLinkNotice({
    super.key,
    required this.kind,
    required this.onOpen,
    required this.onDismiss,
  });

  final ForumClipboardLinkKind kind;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final label = switch (kind) {
      ForumClipboardLinkKind.thread => l10n.clipboardLinkFoundThread,
      ForumClipboardLinkKind.threadPost => l10n.clipboardLinkFoundPost,
      ForumClipboardLinkKind.forum => l10n.clipboardLinkFoundForum,
    };
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Material(
          key: const Key('forum-clipboard-link-notice'),
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              top: 4,
              bottom: 4,
              right: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(liveRegion: true, child: Text(label)),
                ),
                TextButton(
                  key: const Key('forum-clipboard-link-open'),
                  onPressed: onOpen,
                  child: Text(l10n.clipboardLinkOpen),
                ),
                IconButton(
                  key: const Key('forum-clipboard-link-dismiss'),
                  tooltip: l10n.commonClose,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
