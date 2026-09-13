import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/thread/presentation/services/thread_post_actions.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComicCommentActionBar extends ConsumerWidget {
  const ComicCommentActionBar({
    super.key,
    required this.controller,
    required this.session,
  });
  final ComicCommentInteractionController controller;
  final ComicCommentSessionController session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final data = controller.context;
      final busy =
          controller.isLoading ||
          controller.isBusy ||
          session.state.isRefreshing;
      final failed = controller.result?.failureOrNull != null;
      final unavailable = <String>[
        if (data != null && !data.canRate) l10n.comicRatingUnavailable,
        if (data != null && !data.canComment) l10n.comicPostCommentUnavailable,
        if (data != null && !data.canReply) l10n.comicReplyUnavailable,
      ];
      return Material(
        key: const Key('comic-comment-action-bar'),
        color: ThreadDetailNativePalette.resolve(Theme.of(context)).card,
        elevation: 6,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed || session.state.refreshFailed)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.state.refreshFailed
                              ? l10n.comicCommentRefreshFailed
                              : l10n.comicInteractionLoadFailed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => controller.load(force: true),
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                if (!failed && unavailable.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      unavailable.join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (session.state.isRefreshing)
                  const LinearProgressIndicator(
                    key: Key('comic-comment-refresh-progress'),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('comic-comment-rate-button'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: busy || data?.canRate != true
                            ? null
                            : () => _perform(context, ref, _CommentAction.rate),
                        icon: _icon(
                          controller.isLoading,
                          Icons.favorite_border,
                        ),
                        label: Text(l10n.threadRatingTitle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('comic-comment-comment-button'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: busy || data?.canComment != true
                            ? null
                            : () => _perform(
                                context,
                                ref,
                                _CommentAction.comment,
                              ),
                        icon: _icon(
                          controller.isLoading,
                          Icons.chat_bubble_outline,
                        ),
                        label: Text(l10n.threadCommentTitle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('comic-comment-reply-button'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: busy || data?.canReply != true
                            ? null
                            : () =>
                                  _perform(context, ref, _CommentAction.reply),
                        icon: _icon(controller.isLoading, Icons.reply_outlined),
                        label: Text(l10n.threadDetailReply),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _icon(bool loading, IconData icon) => loading
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon, size: 20);
  Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    _CommentAction action,
  ) => controller.perform(
    page: action == _CommentAction.reply ? null : 1,
    invoke: (target, current) async {
      final read = session.state.result?.reads[1];
      if (read == null) return false;
      final actions = ThreadPostActions(
        context: context,
        ref: ref,
        target: ThreadPostActionContext(
          tid: target.tid,
          fid: target.fid,
          subject: target.subject,
          page: 1,
          capabilities: read.capabilities,
          sourceUri: target.sourceUri,
        ),
        isCurrent: current,
        imageReferer: target.sourceUri?.toString(),
      );
      return switch (action) {
        _CommentAction.rate => actions.rate(target.firstPost!),
        _CommentAction.comment => actions.comment(target.firstPost!),
        _CommentAction.reply => actions.reply(),
      };
    },
  );
}

enum _CommentAction { rate, comment, reply }
