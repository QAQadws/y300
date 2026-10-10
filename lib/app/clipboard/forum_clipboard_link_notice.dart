import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'forum_clipboard_link_policy.dart';

SnackBar buildForumClipboardLinkSnackBar({
  required BuildContext context,
  required ForumClipboardLinkKind kind,
  required VoidCallback onOpen,
  VoidCallback? onVisible,
  Widget Function(Widget content)? contentWrapper,
}) {
  final l10n = AppLocalizations.of(context);
  final label = switch (kind) {
    ForumClipboardLinkKind.thread => l10n.clipboardLinkFoundThread,
    ForumClipboardLinkKind.threadPost => l10n.clipboardLinkFoundPost,
    ForumClipboardLinkKind.forum => l10n.clipboardLinkFoundForum,
  };
  final content = Text(label);
  return SnackBar(
    // Consecutive presentations need fresh visibility and action state.
    key: UniqueKey(),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 6),
    // The SDK otherwise keeps snackbars with an action visible indefinitely.
    persist: false,
    showCloseIcon: false,
    content: KeyedSubtree(
      key: const Key('forum-clipboard-link-notice'),
      child: contentWrapper?.call(content) ?? content,
    ),
    onVisible: onVisible,
    action: SnackBarAction(
      key: const Key('forum-clipboard-link-open'),
      label: l10n.clipboardLinkOpen,
      onPressed: onOpen,
    ),
  );
}
