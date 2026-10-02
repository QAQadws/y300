import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_action_sheet.dart';

enum ThreadPostAction {
  edit,
  reply,
  rate,
  comment,
  selectCopy,
  copyAll,
  copyFloorLink,
}

class ThreadPostActionSheet extends StatelessWidget {
  const ThreadPostActionSheet({
    super.key,
    required this.post,
    required this.editUri,
    required this.capabilities,
  });

  final ThreadPost post;
  final Uri? editUri;
  final ThreadDetailReadCapabilities? capabilities;

  bool _supports(ThreadDetailCapability capability) {
    return capabilities?.supports(capability) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ForumContentActionSheet<ThreadPostAction>(
      key: const Key('thread-post-action-sheet'),
      actions: [
        if (editUri != null)
          ForumContentAction(
            key: const Key('thread-post-edit-action'),
            value: ThreadPostAction.edit,
            icon: Icons.edit_outlined,
            label: l10n.threadDetailEdit,
          ),
        if (_supports(ThreadDetailCapability.replyAction))
          ForumContentAction(
            key: const Key('thread-post-reply-action'),
            value: ThreadPostAction.reply,
            icon: Icons.reply_outlined,
            label: l10n.threadDetailReply,
          ),
        if (_supports(ThreadDetailCapability.ratingAction) &&
            post.rateUrl?.trim().isNotEmpty == true)
          ForumContentAction(
            key: const Key('thread-post-rate-action'),
            value: ThreadPostAction.rate,
            icon: Icons.favorite_border,
            label: l10n.threadRatingTitle,
          ),
        if (_supports(ThreadDetailCapability.commentAction) &&
            post.commentUrl?.trim().isNotEmpty == true)
          ForumContentAction(
            key: const Key('thread-post-comment-action'),
            value: ThreadPostAction.comment,
            icon: Icons.chat_bubble_outline,
            label: l10n.threadCommentTitle,
          ),
        ForumContentAction(
          key: const Key('thread-post-select-copy-action'),
          value: ThreadPostAction.selectCopy,
          icon: Icons.text_fields,
          label: l10n.threadDetailSelectCopy,
        ),
        ForumContentAction(
          key: const Key('thread-post-copy-all-action'),
          value: ThreadPostAction.copyAll,
          icon: Icons.copy_all_outlined,
          label: l10n.threadDetailCopyAll,
        ),
        ForumContentAction(
          key: const Key('thread-post-copy-floor-link-action'),
          value: ThreadPostAction.copyFloorLink,
          icon: Icons.link_outlined,
          label: l10n.threadDetailCopyFloorLink,
        ),
      ],
    );
  }
}
