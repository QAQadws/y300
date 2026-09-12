import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_controller.dart';
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
  const BlogCommentPage({super.key, required this.target});

  final UserBlogCommentTarget target;

  @override
  ConsumerState<BlogCommentPage> createState() => _BlogCommentPageState();
}

class _BlogCommentPageState extends ConsumerState<BlogCommentPage> {
  late final BlogCommentController _controller;
  final _text = TextEditingController();
  bool _confirmingLeave = false;
  UserBlogCommentReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    _controller = BlogCommentController(
      target: widget.target,
      service: ref.read(userBlogCommentServiceProvider),
      currentActor: () => ref.read(blogAccountIdProvider),
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
    final source = _controller.value.message;
    if (_text.text != source) {
      _text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncInput);
    _controller.dispose();
    _text.dispose();
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
          backgroundColor: native.background,
          appBar: AppBar(
            title: Text(blogCommentActionLabel(l10n, widget.target.action)),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (state.busy) ...[
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
                if (state.phase == BlogCommentPhase.expired)
                  Text(
                    l10n.profileBlogCommentSessionChanged,
                    style: TextStyle(color: native.body),
                  )
                else ...[
                  if (deleting)
                    Text(
                      l10n.profileBlogDeleteCommentBody,
                      style: TextStyle(color: native.body),
                    )
                  else
                    TextField(
                      key: const Key('blog-comment-input'),
                      controller: _text,
                      enabled: !state.busy,
                      readOnly: state.phase == BlogCommentPhase.unknown,
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: native.body),
                      decoration: InputDecoration(
                        labelText: l10n.profileBlogCommentContent,
                      ),
                      onChanged: _controller.updateMessage,
                    ),
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
                  const SizedBox(height: 16),
                  if (state.phase == BlogCommentPhase.failed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const Key('blog-comment-retry'),
                        onPressed: _controller.prepare,
                        child: Text(l10n.commonRetry),
                      ),
                    )
                  else if (state.phase != BlogCommentPhase.unknown)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: const Key('blog-comment-submit'),
                        onPressed: state.phase == BlogCommentPhase.ready
                            ? _submit
                            : null,
                        child: Text(
                          deleting
                              ? l10n.commonDelete
                              : widget.target.action ==
                                    UserBlogCommentAction.edit
                              ? l10n.commonSave
                              : l10n.profileBlogSubmitComment,
                        ),
                      ),
                    ),
                  if (state.phase == BlogCommentPhase.failed)
                    TextButton(
                      key: const Key('blog-comment-open-web'),
                      onPressed: _openWeb,
                      child: Text(l10n.profileBlogOpenWeb),
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
