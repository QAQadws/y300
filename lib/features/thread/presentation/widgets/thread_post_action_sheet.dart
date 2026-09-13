import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';

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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('thread-post-action-sheet'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editUri != null)
                ListTile(
                  key: const Key('thread-post-edit-action'),
                  dense: true,
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.threadDetailEdit),
                  onTap: () => Navigator.of(context).pop(ThreadPostAction.edit),
                ),
              if (_supports(ThreadDetailCapability.replyAction))
                ListTile(
                  key: const Key('thread-post-reply-action'),
                  dense: true,
                  leading: const Icon(Icons.reply_outlined),
                  title: Text(l10n.threadDetailReply),
                  onTap: () =>
                      Navigator.of(context).pop(ThreadPostAction.reply),
                ),
              if (_supports(ThreadDetailCapability.ratingAction) &&
                  post.rateUrl?.trim().isNotEmpty == true)
                ListTile(
                  key: const Key('thread-post-rate-action'),
                  dense: true,
                  leading: const Icon(Icons.favorite_border),
                  title: Text(l10n.threadRatingTitle),
                  onTap: () => Navigator.of(context).pop(ThreadPostAction.rate),
                ),
              if (_supports(ThreadDetailCapability.commentAction) &&
                  post.commentUrl?.trim().isNotEmpty == true)
                ListTile(
                  key: const Key('thread-post-comment-action'),
                  dense: true,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(l10n.threadCommentTitle),
                  onTap: () =>
                      Navigator.of(context).pop(ThreadPostAction.comment),
                ),
              ListTile(
                key: const Key('thread-post-select-copy-action'),
                dense: true,
                leading: const Icon(Icons.text_fields),
                title: Text(l10n.threadDetailSelectCopy),
                onTap: () =>
                    Navigator.of(context).pop(ThreadPostAction.selectCopy),
              ),
              ListTile(
                key: const Key('thread-post-copy-all-action'),
                dense: true,
                leading: const Icon(Icons.copy_all_outlined),
                title: Text(l10n.threadDetailCopyAll),
                onTap: () =>
                    Navigator.of(context).pop(ThreadPostAction.copyAll),
              ),
              ListTile(
                key: const Key('thread-post-copy-floor-link-action'),
                dense: true,
                leading: const Icon(Icons.link_outlined),
                title: Text(l10n.threadDetailCopyFloorLink),
                onTap: () =>
                    Navigator.of(context).pop(ThreadPostAction.copyFloorLink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
