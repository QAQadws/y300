import 'package:flutter/material.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/thread/domain/services/post_edit_target_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/services/thread_post_comment_flow.dart';
import 'package:y300/features/thread/presentation/services/thread_post_comment_service.dart';
import 'package:y300/features/thread/presentation/services/thread_post_edit_flow.dart';
import 'package:y300/features/thread/presentation/services/thread_post_navigation.dart';
import 'package:y300/features/thread/presentation/services/thread_post_rating_flow.dart';
import 'package:y300/features/thread/presentation/services/thread_post_rating_service.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_action_sheet.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

enum ThreadPostMutation { post, reply }

/// Immutable source-page identity; feed pagination never substitutes its last
/// loaded page for the page containing the selected floor.
class ThreadPostActionContext {
  const ThreadPostActionContext({
    required this.tid,
    required this.fid,
    required this.subject,
    required this.page,
    required this.capabilities,
    this.sourceUri,
  });
  final String tid;
  final String fid;
  final String subject;
  final int page;
  final ThreadDetailReadCapabilities? capabilities;
  final Uri? sourceUri;
  bool supports(ThreadDetailCapability value) =>
      capabilities?.supports(value) ?? false;
}

/// Shares interaction routes and forms; each host owns its refresh lifecycle.
class ThreadPostActions {
  ThreadPostActions({
    required this.context,
    required this.ref,
    required this.target,
    required this.isCurrent,
    required this.imageReferer,
  });
  final BuildContext context;
  final WidgetRef ref;
  final ThreadPostActionContext target;
  final bool Function() isCurrent;
  final String? imageReferer;
  bool get active => context.mounted && isCurrent();
  late final ThreadPostNavigation navigation = ThreadPostNavigation(
    context: context,
    ref: ref,
    tid: target.tid,
    routeSession: ThreadPostNavigationSession(),
    imageReferer: imageReferer,
    isCurrent: isCurrent,
  );

  PostEditTarget? _editTarget(ThreadPost post) =>
      !target.supports(ThreadDetailCapability.editAction)
      ? null
      : ref
            .read(postEditTargetParserProvider)
            .parse(
              rawUrl: post.editUrl ?? '',
              currentTid: target.tid,
              currentPid: post.pid,
              currentFid: target.fid,
              currentPage: target.page,
              isFirstPost: post.isFirst,
            )
            .target;

  Future<ThreadPostMutation?> show({
    required ThreadPost sourcePost,
    required ThreadPost displayPost,
    required ThreadPostBodyRenderPlan plan,
  }) async {
    if (!active) return null;
    final editTarget = _editTarget(sourcePost);
    final action = await showModalBottomSheet<ThreadPostAction>(
      context: context,
      builder: (_) => ThreadPostActionSheet(
        post: sourcePost,
        editUri: editTarget?.editUri,
        capabilities: target.capabilities,
      ),
    );
    if (!context.mounted || !isCurrent() || action == null) return null;
    switch (action) {
      case ThreadPostAction.reply:
        return await reply(sourcePost) ? ThreadPostMutation.reply : null;
      case ThreadPostAction.rate:
        return await rate(sourcePost) ? ThreadPostMutation.post : null;
      case ThreadPostAction.comment:
        return await comment(sourcePost) ? ThreadPostMutation.post : null;
      case ThreadPostAction.edit:
        if (editTarget == null) return null;
        var changed = false;
        await ThreadPostEditFlow(
          context: context,
          ref: ref,
          isCurrent: isCurrent,
          onMutation: () async {
            changed = true;
          },
        ).open(editTarget);
        return changed ? ThreadPostMutation.post : null;
      case ThreadPostAction.selectCopy:
        final selectionSession = ThreadPostNavigationSession();
        try {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (selectionContext) {
                final selectionNavigation = ThreadPostNavigation(
                  context: selectionContext,
                  ref: ref,
                  tid: target.tid,
                  imageReferer: imageReferer,
                  isCurrent: () => active && selectionContext.mounted,
                  routeSession: selectionSession,
                );
                return ThreadPostHtmlSelectionCopyPage(
                  post: displayPost,
                  sourcePost: sourcePost,
                  threadId: target.tid,
                  imageReferer: imageReferer ?? '',
                  plan: plan,
                  onOpenPostLink: selectionNavigation.openLink,
                  onOpenPostImage: selectionNavigation.openImages,
                  onImageFallback: selectionNavigation.copyImageUrl,
                );
              },
            ),
          );
        } finally {
          selectionSession.dispose();
        }
      case ThreadPostAction.copyAll:
        await navigation.copyPlainText(sourcePost, plan);
      case ThreadPostAction.copyFloorLink:
        await navigation.copyFloorLink(sourcePost);
    }
    return null;
  }

  Future<bool> rate(ThreadPost post) async {
    if (!active ||
        !target.supports(ThreadDetailCapability.ratingAction) ||
        post.rateUrl?.trim().isNotEmpty != true) {
      return false;
    }
    final service = ref.read(threadPostRatingServiceProvider);
    final result = await showThreadPostRatingFlow(
      context: context,
      ref: ref,
      load: () => service.load(
        tid: target.tid,
        post: post,
        referer: target.sourceUri?.replace(fragment: 'pid${post.pid}'),
      ),
      submit: service.submit,
      isCurrent: isCurrent,
    );
    return result is DataCommandApplied<ThreadPostRatingReceipt>;
  }

  Future<bool> comment(ThreadPost post) async {
    if (!active ||
        !target.supports(ThreadDetailCapability.commentAction) ||
        post.commentUrl?.trim().isNotEmpty != true) {
      return false;
    }
    final service = ref.read(threadPostCommentServiceProvider);
    final result = await showThreadPostCommentFlow(
      context: context,
      ref: ref,
      load: () => service.load(
        tid: target.tid,
        page: target.page,
        post: post,
        referer: target.sourceUri?.replace(fragment: 'pid${post.pid}'),
      ),
      submit: service.submit,
      isCurrent: isCurrent,
    );
    return result is DataCommandApplied<ThreadPostCommentReceipt>;
  }

  Future<bool> reply([ThreadPost? post]) async {
    if (!active || !target.supports(ThreadDetailCapability.replyAction)) {
      return false;
    }
    final replyUri = post == null ? null : Uri.tryParse(post.replyUrl ?? '');
    if (target.fid.trim().isEmpty ||
        target.tid.trim().isEmpty ||
        (post != null &&
            (post.replyUrl?.trim().isNotEmpty != true || replyUri == null))) {
      if (post != null) {
        await navigation.copyUrl(
          AppLocalizations.of(context).threadDetailReplyLink,
          post.replyUrl ?? '',
        );
      }
      return false;
    }
    final result = await Navigator.of(context).push<ReplyComposerResult>(
      MaterialPageRoute(
        builder: (_) => ReplyComposerPage(
          args: ReplyComposerArgs(
            target: post == null
                ? ReplyTarget.thread(
                    fid: target.fid,
                    tid: target.tid,
                    sourceUri: target.sourceUri,
                  )
                : ReplyTarget.post(
                    fid: target.fid,
                    tid: target.tid,
                    pid: post.pid,
                    sourceUri: replyUri,
                  ),
            replyFormUri: replyUri,
            title: post == null ? target.subject : null,
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
  }
}
