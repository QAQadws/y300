import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_fields.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_web_navigation.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef BlogEditorResult = ({UserBlogReceipt receipt, String subject});

class BlogEditorPage extends ConsumerStatefulWidget {
  const BlogEditorPage({super.key, required this.target});
  final UserBlogTarget target;
  @override
  ConsumerState<BlogEditorPage> createState() => _BlogEditorPageState();
}

class _BlogEditorPageState extends ConsumerState<BlogEditorPage> {
  late final BlogEditorController _controller;
  final _subject = TextEditingController();
  final _tags = TextEditingController();
  final _categoryName = TextEditingController();
  bool _preview = false;
  bool _creatingCategory = false;
  bool _categoryNameRequired = false;
  bool _showServerVersion = false;
  bool _dialogOpen = false;
  bool _leaving = false;
  bool _finishScheduled = false;
  bool _routeCurrent = true;
  UserBlogReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    _controller = BlogEditorController(
      target: widget.target,
      service: ref.read(userBlogOperationsProvider),
      currentActor: () => ref.read(blogAccountIdProvider),
    );
    _controller.addListener(_syncInputs);
    ref.listenManual(blogAccountIdProvider, (_, actor) {
      if (actor != widget.target.actorUserId) {
        _receipt = null;
        _controller.expire();
      }
    });
    unawaited(_controller.prepare());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _scheduleFinish();
  }

  void _syncInputs() {
    final draft = _controller.value.draft;
    for (final (controller, text) in [
      (_subject, draft.subject),
      (_tags, draft.tags),
      (_categoryName, draft.newPersonalCategory),
    ]) {
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncInputs);
    _controller.dispose();
    _subject.dispose();
    _tags.dispose();
    _categoryName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_creatingCategory && _categoryName.text.trim().isEmpty) {
      setState(() => _categoryNameRequired = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).profileBlogNewCategoryNameRequired,
          ),
        ),
      );
      return;
    }
    final receipt = await _controller.submit();
    if (!mounted || _leaving) return;
    if (receipt == null) {
      final issue = _controller.value.issue;
      if (issue != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_issueText(AppLocalizations.of(context), issue)),
          ),
        );
      }
      return;
    }
    if (ref.read(blogAccountIdProvider) != widget.target.actorUserId) return;
    _receipt = receipt;
    ref.read(blogMutationBusProvider).publish(receipt);
    _scheduleFinish();
  }

  void _scheduleFinish() {
    if (_receipt == null ||
        _dialogOpen ||
        !_routeCurrent ||
        _leaving ||
        _finishScheduled) {
      return;
    }
    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishScheduled = false;
      if (!mounted ||
          _dialogOpen ||
          !_routeCurrent ||
          _leaving ||
          _receipt == null ||
          _controller.value.phase != BlogEditorPhase.applied ||
          ref.read(blogAccountIdProvider) != widget.target.actorUserId) {
        return;
      }
      Navigator.of(context).pop<BlogEditorResult>((
        receipt: _receipt!,
        subject: _controller.value.draft.subject,
      ));
    });
    // Receipt completion itself may not leave an animation running.
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required Key confirmKey,
  }) async {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: confirmKey,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (mounted) _scheduleFinish();
    return result == true;
  }

  Future<void> _confirmLeave() async {
    if (_dialogOpen) return;
    final l10n = AppLocalizations.of(context);
    final uncertain =
        _controller.value.phase == BlogEditorPhase.submitting ||
        _controller.value.phase == BlogEditorPhase.unknown;
    final leave = await _confirm(
      title: l10n.profileBlogLeaveEditorTitle,
      message: uncertain
          ? l10n.profileBlogLeavePendingEditor
          : l10n.profileBlogLeaveEditorBody,
      confirmKey: const Key('blog-editor-leave'),
    );
    if (mounted && leave && _receipt == null) Navigator.of(context).pop();
  }

  Future<void> _openWeb() async {
    if (_dialogOpen ||
        !{
          BlogEditorPhase.ready,
          BlogEditorPhase.failed,
        }.contains(_controller.value.phase)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context);
    if (_controller.value.dirty &&
        !await _confirm(
          title: l10n.profileBlogOpenWeb,
          message: l10n.profileBlogWebInputNotice,
          confirmKey: const Key('blog-editor-confirm-web'),
        )) {
      return;
    }
    if (!mounted ||
        !{
          BlogEditorPhase.ready,
          BlogEditorPhase.failed,
        }.contains(_controller.value.phase)) {
      return;
    }
    await openBlogWebPage(
      context,
      ref,
      expectedActor: widget.target.actorUserId,
      replaceCurrent: true,
      destination: (navigation) => navigation.editor(widget.target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final native = Theme.of(context).y300NativeContent;
    final creating = widget.target.action == UserBlogAction.create;
    final owner =
        'blog-editor-${widget.target.actorUserId}-${widget.target.blogId ?? 'new'}';
    return ValueListenableBuilder<BlogEditorState>(
      valueListenable: _controller,
      builder: (context, state, _) => PopScope<BlogEditorResult>(
        canPop:
            !state.dirty &&
            state.phase != BlogEditorPhase.submitting &&
            state.phase != BlogEditorPhase.unknown,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _leaving = true;
          } else {
            unawaited(_confirmLeave());
          }
        },
        child: Scaffold(
          backgroundColor: native.background,
          appBar: AppBar(
            title: Text(
              creating ? l10n.profileBlogWrite : l10n.profileBlogEdit,
            ),
            actions: [
              if (state.options != null)
                IconButton(
                  key: const Key('blog-editor-preview-toggle'),
                  tooltip: _preview
                      ? l10n.profileBlogBackToEditor
                      : l10n.composerPreview,
                  icon: Icon(
                    _preview ? Icons.edit_outlined : Icons.preview_outlined,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _preview = !_preview);
                  },
                ),
              IconButton(
                key: const Key('blog-editor-submit'),
                tooltip: creating ? l10n.profileBlogPublish : l10n.commonSave,
                onPressed: state.canSubmit ? _submit : null,
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              key: const Key('blog-editor-scroll'),
              padding: const EdgeInsets.all(12),
              children: [
                if (state.busy) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      state.phase == BlogEditorPhase.preparing
                          ? l10n.profileBlogPreparingEditor
                          : l10n.profileBlogSubmittingEditor,
                      style: TextStyle(color: native.supportingText),
                    ),
                  ),
                  if (!MediaQuery.disableAnimationsOf(context)) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 12),
                ],
                if (state.phase == BlogEditorPhase.expired)
                  Text(
                    l10n.forumWebViewAccountChanged,
                    style: TextStyle(color: native.body),
                  ),
                if (state.phase == BlogEditorPhase.unknown ||
                    state.failure != null ||
                    state.issue != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      state.phase == BlogEditorPhase.unknown
                          ? l10n.profileBlogEditorOutcomeUnknown
                          : state.issue != null
                          ? _issueText(l10n, state.issue!)
                          : LocalizedErrorSummary.resolve(l10n, state.failure),
                      style: TextStyle(color: native.body),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (state.needsReview) ...[
                  Text(
                    l10n.profileBlogServerChanged,
                    style: TextStyle(color: native.body),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        key: const Key('blog-editor-show-server'),
                        onPressed: () => setState(
                          () => _showServerVersion = !_showServerVersion,
                        ),
                        child: Text(l10n.postEditServerVersion),
                      ),
                      TextButton(
                        key: const Key('blog-editor-use-server'),
                        onPressed: state.busy
                            ? null
                            : () {
                                setState(() {
                                  _creatingCategory = false;
                                  _categoryNameRequired = false;
                                  _showServerVersion = false;
                                });
                                _controller.reviewServerVersion(
                                  keepLocal: false,
                                );
                              },
                        child: Text(l10n.profileBlogUseServer),
                      ),
                      TextButton(
                        key: const Key('blog-editor-keep-local'),
                        onPressed: state.busy
                            ? null
                            : () {
                                setState(() => _showServerVersion = false);
                                _controller.reviewServerVersion(
                                  keepLocal: true,
                                );
                              },
                        child: Text(l10n.profileBlogKeepLocal),
                      ),
                    ],
                  ),
                  if (_showServerVersion && state.serverVersion != null) ...[
                    BlogEditorServerMetadata(
                      draft: state.serverVersion!,
                      options: state.options!,
                    ),
                    BlogEditorPreview(
                      draft: state.serverVersion!,
                      ownerId: owner,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                if (state.options != null) ...[
                  Offstage(
                    offstage: _preview,
                    child: BlogEditorFields(
                      state: state,
                      subject: _subject,
                      tags: _tags,
                      categoryName: _categoryName,
                      creatingCategory: _creatingCategory,
                      categoryNameRequired: _categoryNameRequired,
                      onCreateCategory: (value) => setState(() {
                        _creatingCategory = value;
                        _categoryNameRequired = false;
                      }),
                      onChanged: (change) {
                        final draft = change(_controller.value.draft);
                        if (_categoryNameRequired &&
                            draft.newPersonalCategory.trim().isNotEmpty) {
                          setState(() => _categoryNameRequired = false);
                        }
                        _controller.update(draft);
                      },
                    ),
                  ),
                  if (_preview)
                    BlogEditorPreview(draft: state.draft, ownerId: owner),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ({
                      BlogEditorPhase.ready,
                      BlogEditorPhase.failed,
                    }.contains(state.phase))
                      TextButton(
                        key: const Key('blog-editor-open-web'),
                        onPressed: _openWeb,
                        child: Text(l10n.profileBlogOpenWeb),
                      ),
                    if (state.phase == BlogEditorPhase.failed)
                      FilledButton(
                        key: const Key('blog-editor-retry'),
                        onPressed: _controller.prepare,
                        child: Text(l10n.commonRetry),
                      )
                    else if (state.options != null &&
                        state.phase != BlogEditorPhase.unknown)
                      FilledButton(
                        key: const Key('blog-editor-save'),
                        onPressed: state.canSubmit ? _submit : null,
                        child: Text(
                          creating ? l10n.profileBlogPublish : l10n.commonSave,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _issueText(
  AppLocalizations l10n,
  BlogEditorIssue issue,
) => switch (issue) {
  BlogEditorIssue.subjectRequired => l10n.profileBlogSubjectRequired,
  BlogEditorIssue.bodyRequired => l10n.profileBlogBodyRequired,
  BlogEditorIssue.siteCategoryRequired => l10n.profileBlogSiteCategoryRequired,
  BlogEditorIssue.categoryUnavailable => l10n.profileBlogCategoryUnavailable,
  BlogEditorIssue.newCategoryUnavailable =>
    l10n.profileBlogNewCategoryUnavailable,
  BlogEditorIssue.categoryConflict => l10n.profileBlogCategoryConflict,
  BlogEditorIssue.feedUnavailable => l10n.profileBlogFeedUnavailable,
  BlogEditorIssue.serverChanged => l10n.profileBlogServerChanged,
};
