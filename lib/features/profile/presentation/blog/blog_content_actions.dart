import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_selection_copy_page.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_plain_text_extractor.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_action_sheet.dart';

bool blogCanReplyToArticle(
  UserBlogDetailData article,
  UserBlogDetailReadCapabilities? capabilities,
) =>
    capabilities?.supports(UserBlogDetailCapability.commentingAvailability) ==
        true &&
    article.commentsOpen == true;

/// Owns the transient reader actions while existing pages own write workflows.
class BlogContentActions extends ConsumerStatefulWidget {
  const BlogContentActions({
    super.key,
    required this.article,
    required this.capabilities,
    required this.displayHtml,
    required this.imageReferer,
    required this.linkBaseUri,
    required this.onComment,
    required this.builder,
    this.comment,
    this.onArticleAction,
  });

  final UserBlogDetailData article;
  final UserBlogDetailReadCapabilities? capabilities;
  final String displayHtml;
  final String imageReferer;
  final Uri? linkBaseUri;
  final void Function(UserBlogCommentAction, UserBlogComment?) onComment;
  final Widget Function(VoidCallback onOpenActions) builder;
  final UserBlogComment? comment;
  final ValueChanged<UserBlogAction>? onArticleAction;

  @override
  ConsumerState<BlogContentActions> createState() => _BlogContentActionsState();
}

enum _BlogContentAction {
  reply('reply'),
  edit('edit'),
  delete('delete'),
  pin('pin'),
  unpin('unpin'),
  selectCopy('select-copy'),
  copyAll('copy-all'),
  copyLink('copy-link');

  const _BlogContentAction(this.keyName);
  final String keyName;
}

class _BlogContentActionsState extends ConsumerState<BlogContentActions> {
  bool _opening = false;

  (String, String, String?) get _identity => (
    widget.article.ownerUserId,
    widget.article.blogId,
    widget.comment?.commentId,
  );

  Uri? get _link => ref
      .read(userBlogNavigationProvider)
      ?.detail(
        UserBlogDetailQuery(
          ownerUserId: widget.article.ownerUserId,
          blogId: widget.article.blogId,
          commentId: widget.comment?.commentId,
        ),
      );

  bool _canAct(Object owner, (String, String, String?) identity) =>
      mounted &&
      identical(ref.read(blogMutationBusProvider), owner) &&
      identity == _identity &&
      ModalRoute.of(context)?.isCurrent != false;

  List<ForumContentAction<_BlogContentAction>> _actions(
    AppLocalizations l10n,
    Uri? link,
  ) {
    final result = <ForumContentAction<_BlogContentAction>>[];
    void add(_BlogContentAction value, String label, IconData icon) {
      result.add(
        ForumContentAction(
          value: value,
          label: label,
          icon: icon,
          key: Key('blog-content-action-${value.keyName}'),
        ),
      );
    }

    final comment = widget.comment;
    if (comment == null) {
      if (blogCanReplyToArticle(widget.article, widget.capabilities)) {
        add(
          _BlogContentAction.reply,
          l10n.profileBlogReply,
          Icons.reply_outlined,
        );
      }
      if (widget.onArticleAction != null) {
        for (final (action, value, icon) in const [
          (UserBlogAction.edit, _BlogContentAction.edit, Icons.edit_outlined),
          (
            UserBlogAction.delete,
            _BlogContentAction.delete,
            Icons.delete_outlined,
          ),
          (UserBlogAction.pin, _BlogContentAction.pin, Icons.push_pin_outlined),
          (UserBlogAction.unpin, _BlogContentAction.unpin, Icons.push_pin),
        ]) {
          if (widget.article.actions.contains(action)) {
            add(value, blogActionLabel(l10n, action), icon);
          }
        }
      }
    } else {
      for (final (action, value, icon) in const [
        (
          UserBlogCommentAction.reply,
          _BlogContentAction.reply,
          Icons.reply_outlined,
        ),
        (
          UserBlogCommentAction.edit,
          _BlogContentAction.edit,
          Icons.edit_outlined,
        ),
        (
          UserBlogCommentAction.delete,
          _BlogContentAction.delete,
          Icons.delete_outlined,
        ),
      ]) {
        if (comment.actions.contains(action)) {
          add(value, blogCommentActionLabel(l10n, action), icon);
        }
      }
    }
    add(
      _BlogContentAction.selectCopy,
      l10n.threadDetailSelectCopy,
      Icons.text_fields,
    );
    add(
      _BlogContentAction.copyAll,
      l10n.threadDetailCopyAll,
      Icons.copy_all_outlined,
    );
    if (link != null) {
      add(
        _BlogContentAction.copyLink,
        l10n.threadDetailCopyLink,
        Icons.link_outlined,
      );
    }
    return result;
  }

  Future<void> _openActions() async {
    if (!mounted || _opening || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _opening = true;
    final owner = ref.read(blogMutationBusProvider);
    final identity = _identity;
    final actions = _actions(AppLocalizations.of(context), _link);
    try {
      final action = await showModalBottomSheet<_BlogContentAction>(
        context: context,
        builder: (_) => _BlogContentActionSessionSheet(
          accountOwner: owner,
          actions: actions,
        ),
      );
      if (!mounted || action == null || !_canAct(owner, identity)) return;
      final l10n = AppLocalizations.of(context);
      final link = _link;
      // A refresh may revoke an advertised operation while its sheet is open.
      if (!_actions(l10n, link).any((item) => item.value == action)) return;
      final comment = widget.comment;
      switch (action) {
        case _BlogContentAction.reply:
          widget.onComment(
            comment == null
                ? UserBlogCommentAction.add
                : UserBlogCommentAction.reply,
            comment,
          );
        case _BlogContentAction.edit:
          if (comment == null) {
            widget.onArticleAction?.call(UserBlogAction.edit);
          } else {
            widget.onComment(UserBlogCommentAction.edit, comment);
          }
        case _BlogContentAction.delete:
          if (comment == null) {
            widget.onArticleAction?.call(UserBlogAction.delete);
          } else {
            widget.onComment(UserBlogCommentAction.delete, comment);
          }
        case _BlogContentAction.pin:
          widget.onArticleAction?.call(UserBlogAction.pin);
        case _BlogContentAction.unpin:
          widget.onArticleAction?.call(UserBlogAction.unpin);
        case _BlogContentAction.selectCopy:
          final page = BlogSelectionCopyPage(
            displayHtml: widget.displayHtml,
            accountOwner: owner,
            sourceId: comment == null
                ? 'profile-blog-${widget.article.blogId}'
                : 'profile-blog-comment-${comment.commentId}',
            cacheOwnerId: comment?.commentId ?? widget.article.blogId,
            imageReferer: widget.imageReferer,
            linkBaseUri: widget.linkBaseUri,
          );
          await Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => page));
        case _BlogContentAction.copyAll:
          final plan = const ThreadPostBodyRenderPlanner().plan(
            widget.displayHtml,
          );
          final text = const ThreadPostBodyPlainTextExtractor().extract(
            plan.document,
          );
          await _copy(text, l10n.threadDetailPostBody, owner, identity);
        case _BlogContentAction.copyLink:
          if (link != null) {
            await _copy(link.toString(), l10n.composerLink, owner, identity);
          }
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _copy(
    String text,
    String label,
    Object owner,
    (String, String, String?) identity,
  ) async {
    if (text.trim().isEmpty || !_canAct(owner, identity)) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || !_canAct(owner, identity)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).threadDetailCopySuccess(label),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.builder(_openActions);
}

class _BlogContentActionSessionSheet extends ConsumerStatefulWidget {
  const _BlogContentActionSessionSheet({
    required this.accountOwner,
    required this.actions,
  });

  final Object accountOwner;
  final List<ForumContentAction<_BlogContentAction>> actions;

  @override
  ConsumerState<_BlogContentActionSessionSheet> createState() =>
      _BlogContentActionSessionSheetState();
}

class _BlogContentActionSessionSheetState
    extends ConsumerState<_BlogContentActionSessionSheet> {
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(blogMutationBusProvider, (_, owner) {
      if (!identical(owner, widget.accountOwner) && !_expired) {
        setState(() => _expired = true);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context).profileBlogCommentSessionChanged,
          ),
        ),
      );
    }
    return ForumContentActionSheet<_BlogContentAction>(
      key: const Key('blog-content-action-sheet'),
      actions: widget.actions,
    );
  }
}
