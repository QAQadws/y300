import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_sticker_text_controller.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_editor.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_web_navigation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

String blogCommentActionLabel(
  AppLocalizations l10n,
  UserBlogCommentAction action,
) => switch (action) {
  UserBlogCommentAction.add => l10n.profileBlogComment,
  UserBlogCommentAction.reply => l10n.profileBlogReplyComment,
  UserBlogCommentAction.edit => l10n.profileBlogEditComment,
  UserBlogCommentAction.delete => l10n.profileBlogDeleteComment,
};

/// One route owns the prepared form, original source text and submission.
/// Inputs are deliberately transient and are cleared when the actor changes.
class BlogCommentPage extends ConsumerStatefulWidget {
  const BlogCommentPage({super.key, required this.target, this.refreshOrigin});

  final UserBlogCommentTarget target;
  final Object? refreshOrigin;

  @override
  ConsumerState<BlogCommentPage> createState() => _BlogCommentPageState();
}

class _BlogCommentPageState extends ConsumerState<BlogCommentPage> {
  late final BlogCommentController _controller;
  late final ComposerStickerTextController _input;
  bool _confirmingLeave = false;
  bool _pickerOpen = false;
  ModalRoute<Object?>? _smileyRoute;
  UserBlogCommentReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    _controller = BlogCommentController(
      target: widget.target,
      service: ref.read(userBlogCommentServiceProvider),
      currentActor: () => ref.read(blogAccountIdProvider),
    );
    _input = ComposerStickerTextController(
      value: '',
      readOnly: true,
      onChanged: _controller.updateMessage,
    );
    _controller.addListener(_syncInput);
    ref.listenManual(blogAccountIdProvider, (_, actor) {
      if (actor != widget.target.actorUserId) {
        _receipt = null;
        _controller.expire();
      }
    });
    unawaited(_controller.prepare());
  }

  void _syncInput() {
    final state = _controller.value;
    _input.update(
      value: state.message,
      readOnly: !_canEdit(state),
      stickers: state.smilies.map(blogCommentSticker),
    );
    if (!_canEdit(state)) {
      _input.focusNode.unfocus();
      _closeSmileyPicker();
    }
  }

  bool _canEdit(BlogCommentState state) =>
      state.phase == BlogCommentPhase.ready ||
      state.phase == BlogCommentPhase.failed;

  void _closeSmileyPicker() {
    final route = _smileyRoute;
    _smileyRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _pickSmiley() async {
    final state = _controller.value;
    if (_pickerOpen || !_canEdit(state) || state.smilies.isEmpty) return;
    final generation = _input.generation;
    final selection = _input.selection;
    _input.focusNode.unfocus();
    _pickerOpen = true;
    final smiley = await showModalBottomSheet<UserBlogCommentSmiley>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).y300NativeContent.card,
      builder: (context) {
        _smileyRoute = ModalRoute.of(context);
        // Expiry can arrive after push but before the sheet's first frame.
        // Never render a captured catalog after its editor has been locked.
        if (!_canEdit(_controller.value) ||
            ref.read(blogAccountIdProvider) != widget.target.actorUserId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _closeSmileyPicker();
          });
          return const SizedBox.shrink();
        }
        return BlogCommentSmileySheet(smilies: _controller.value.smilies);
      },
    );
    _smileyRoute = null;
    if (!mounted) return;
    _pickerOpen = false;
    if (smiley == null ||
        ref.read(blogAccountIdProvider) != widget.target.actorUserId ||
        !_canEdit(_controller.value) ||
        !_input.canApplyInsertion(generation, selection)) {
      return;
    }
    _input.insertSticker(blogCommentSticker(smiley));
    _input.focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncInput);
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final native = Theme.of(context).y300NativeContent;
    final deleting = widget.target.action == UserBlogCommentAction.delete;
    return ValueListenableBuilder<BlogCommentState>(
      valueListenable: _controller,
      builder: (context, state, _) => PopScope<UserBlogCommentReceipt>(
        canPop:
            !state.dirty &&
            state.phase != BlogCommentPhase.submitting &&
            state.phase != BlogCommentPhase.unknown,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_confirmLeave());
        },
        child: Scaffold(
          backgroundColor: native.card,
          appBar: AppBar(
            title: Text(blogCommentActionLabel(l10n, widget.target.action)),
          ),
          bottomNavigationBar:
              state.phase == BlogCommentPhase.expired ||
                  state.phase == BlogCommentPhase.unknown
              ? null
              : Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: BlogCommentToolbar(
                    showSmiley: !deleting,
                    onSmiley: _canEdit(state) && state.smilies.isNotEmpty
                        ? _pickSmiley
                        : null,
                    actionKey: Key(
                      state.phase == BlogCommentPhase.failed
                          ? 'blog-comment-retry'
                          : 'blog-comment-submit',
                    ),
                    actionLabel: state.phase == BlogCommentPhase.failed
                        ? l10n.commonRetry
                        : deleting
                        ? l10n.commonDelete
                        : widget.target.action == UserBlogCommentAction.edit
                        ? l10n.commonSave
                        : l10n.profileBlogSubmitComment,
                    actionIcon: state.phase == BlogCommentPhase.failed
                        ? Icons.refresh
                        : deleting
                        ? Icons.delete_outline
                        : widget.target.action == UserBlogCommentAction.edit
                        ? Icons.check
                        : Icons.send_outlined,
                    onAction: state.phase == BlogCommentPhase.failed
                        ? _controller.prepare
                        : state.phase == BlogCommentPhase.ready
                        ? _submit
                        : null,
                    onOpenWeb: state.phase == BlogCommentPhase.failed
                        ? _openWeb
                        : null,
                  ),
                ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              key: const Key('blog-comment-scroll'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.busy) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              state.phase == BlogCommentPhase.preparing
                                  ? l10n.profileBlogPreparingComment
                                  : l10n.profileBlogSubmittingComment,
                              style: TextStyle(color: native.supportingText),
                            ),
                          ),
                          if (!MediaQuery.disableAnimationsOf(context)) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (state.phase == BlogCommentPhase.expired) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.profileBlogCommentSessionChanged,
                            style: TextStyle(color: native.body),
                          ),
                        ] else ...[
                          if (deleting) ...[
                            const SizedBox(height: 16),
                            Text(
                              l10n.profileBlogDeleteCommentBody,
                              style: TextStyle(color: native.body),
                            ),
                          ],
                          if (state.phase == BlogCommentPhase.unknown) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                l10n.profileBlogCommentOutcomeUnknown,
                                style: TextStyle(color: native.body),
                              ),
                            ),
                          ] else if (state.failure != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _failureText(l10n, state.failure),
                                style: TextStyle(color: native.body),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                if (state.phase != BlogCommentPhase.expired && !deleting) ...[
                  if (state.replyTo case final comment?)
                    SliverToBoxAdapter(
                      child: BlogCommentReplyContext(comment: comment),
                    ),
                  SliverFillRemaining(
                    child: BlogCommentInput(controller: _input),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final receipt = await _controller.submit();
    if (!mounted ||
        receipt == null ||
        ref.read(blogAccountIdProvider) != widget.target.actorUserId) {
      return;
    }
    _receipt = receipt;
    ref
        .read(blogMutationBusProvider)
        .publishComment(receipt, origin: widget.refreshOrigin);
    // A leave dialog can cover this route while the POST completes. Let that
    // dialog close first so the receipt never pops the dialog or its parent.
    if (!_confirmingLeave) Navigator.of(context).pop(receipt);
  }

  Future<void> _openWeb() async {
    if (_confirmingLeave) return;
    if (_controller.value.dirty) {
      _confirmingLeave = true;
      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.profileBlogOpenWeb),
          content: Text(l10n.profileBlogWebInputNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              key: const Key('blog-comment-confirm-web'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      );
      _confirmingLeave = false;
      if (!mounted || confirmed != true) return;
    }
    if (!mounted || _controller.value.phase != BlogCommentPhase.failed) return;
    await openBlogWebPage(
      context,
      ref,
      expectedActor: widget.target.actorUserId,
      replaceCurrent: true,
      destination: (navigation) => navigation.comment(widget.target),
    );
  }

  Future<void> _confirmLeave() async {
    if (_confirmingLeave) return;
    _confirmingLeave = true;
    final l10n = AppLocalizations.of(context);
    final uncertain =
        _controller.value.phase == BlogCommentPhase.submitting ||
        _controller.value.phase == BlogCommentPhase.unknown;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.profileBlogLeaveCommentTitle),
        content: Text(
          uncertain
              ? l10n.profileBlogLeavePendingCommentBody
              : l10n.profileBlogLeaveCommentBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('blog-comment-leave'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    _confirmingLeave = false;
    if (!mounted) return;
    if (_receipt != null || leave == true) Navigator.of(context).pop(_receipt);
  }
}

String _failureText(AppLocalizations l10n, Object? failure) =>
    switch (failure) {
      DataCommandFailure(code: 'blog_comment_input_required') =>
        l10n.profileBlogCommentInputRequired,
      DataCommandFailure(code: 'blog_comment_message_invalid') =>
        l10n.profileBlogCommentTooShort,
      _ => LocalizedErrorSummary.resolve(l10n, failure),
    };
