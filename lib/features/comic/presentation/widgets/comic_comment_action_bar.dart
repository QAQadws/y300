import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/thread/presentation/services/thread_post_rating_flow.dart';
import 'package:y300/features/thread/presentation/services/thread_post_rating_service.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

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
    listenable: Listenable.merge([controller, session]),
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final palette = ThreadDetailNativePalette.resolve(Theme.of(context));
      final data = controller.context;
      final busy = controller.isLoading || controller.isBusy;
      final failed = controller.result?.failureOrNull != null;
      final failure = controller.result?.failureOrNull;
      final info = failed
          ? failure?.kind == DataReadFailureKind.unauthorized
                ? l10n.threadLoginRequired
                : l10n.comicInteractionLoadFailed
          : data != null && (!data.canRate || !data.canReply)
          ? !data.canRate && !data.canReply
                ? l10n.comicInteractionUnavailable
                : !data.canRate
                ? l10n.comicRatingUnavailable
                : l10n.comicReplyUnavailable
          : null;
      return Material(
        key: const Key('comic-comment-action-bar'),
        color: palette.card,
        elevation: 6,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      info,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (session.state.refreshFailed)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.comicCommentRefreshFailed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: session.state.isRefreshing
                            ? null
                            : session.retry,
                        child: Text(l10n.commonRetry),
                      ),
                    ],
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
                        ),
                        onPressed: busy || data?.canRate == false
                            ? null
                            : () => _rate(context, ref),
                        icon: _icon(
                          controller.isLoading,
                          Icons.favorite_border,
                        ),
                        label: Text(l10n.threadRatingTitle),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('comic-comment-reply-button'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: busy || data?.canReply == false
                            ? null
                            : () => _reply(context),
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

  Widget _icon(bool busy, IconData icon) => busy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(icon);

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    final service = ref.read(threadPostRatingServiceProvider);
    await controller.perform(
      refreshComments: false,
      invoke: (target, isCurrent) async {
        if (!context.mounted || !isCurrent() || !target.canRate) return false;
        final result = await showThreadPostRatingFlow(
          context: context,
          ref: ref,
          isCurrent: isCurrent,
          load: () => service.load(
            tid: target.tid,
            post: target.firstPost!,
            referer: target.sourceUri,
          ),
          submit: service.submit,
        );
        return result is DataCommandApplied<ThreadPostRatingReceipt>;
      },
    );
  }

  Future<void> _reply(BuildContext context) => controller.perform(
    refreshComments: true,
    invoke: (target, isCurrent) async {
      if (!context.mounted || !isCurrent() || !target.canReply) return false;
      final result = await Navigator.of(context).push<ReplyComposerResult>(
        MaterialPageRoute(
          builder: (_) => ReplyComposerPage(
            args: ReplyComposerArgs(
              target: ReplyTarget.thread(
                fid: target.fid,
                tid: target.tid,
                sourceUri: target.sourceUri,
              ),
              title: target.subject,
            ),
          ),
        ),
      );
      if (result?.sent != true) return false;
      if (context.mounted && isCurrent()) {
        showTransientSnackBar(
          context,
          AppLocalizations.of(context).threadReplySuccess,
        );
      }
      return true;
    },
  );
}
