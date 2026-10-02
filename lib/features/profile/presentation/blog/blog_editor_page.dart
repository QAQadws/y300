import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_media_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_toolbar.dart';
import 'package:y300/features/profile/data/providers/blog_draft_providers.dart';
import 'package:y300/features/profile/domain/models/blog_draft_snapshot.dart';
import 'package:y300/features/profile/presentation/blog/blog_draft_coordinator.dart';
import 'package:y300/features/profile/presentation/blog/blog_draft_mapper.dart';
import 'package:y300/features/profile/presentation/blog/blog_draft_status.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_fields.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_preview.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_settings.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_state.dart';
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

class _BlogEditorPageState extends ConsumerState<BlogEditorPage>
    with WidgetsBindingObserver {
  late final BlogEditorController _controller;
  late final BlogRichTextController _body;
  BlogEditorMediaController? _media;
  BlogDraftCoordinator? _drafts;
  bool _restoringDraft = false;
  bool _didRestoreDraft = false;
  bool _preparingEditor = false;
  bool _closing = false;
  bool _resettingDraft = false;
  bool _allowPop = false;
  final _subject = TextEditingController();
  final _tags = TextEditingController();
  final _categoryName = TextEditingController();
  final _password = TextEditingController();
  final _targetNames = TextEditingController();
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
    WidgetsBinding.instance.addObserver(this);
    if (widget.target.action == UserBlogAction.create) {
      _drafts = BlogDraftCoordinator(
        accountId: widget.target.actorUserId,
        repository: ref.read(blogDraftRepositoryProvider),
      )..addListener(_draftChanged);
    }
    _controller = BlogEditorController(
      target: widget.target,
      service: ref.read(userBlogOperationsProvider),
      currentActor: () => ref.read(blogAccountIdProvider),
      persistBeforeSubmit: _drafts == null
          ? null
          : (draft) async {
              _drafts!.update(
                draft,
                changed: true,
                creatingCategory: _creatingCategory,
                images: _imageHints(),
              );
              return _drafts!.setPending(true);
            },
    );
    _body = BlogRichTextController(
      onChanged: (html) =>
          _controller.update(_controller.value.draft.copyWith(bodyHtml: html)),
    );
    final mediaService = ref.read(userBlogMediaOperationsProvider);
    if (mediaService != null) {
      _media = BlogEditorMediaController(
        picker: ref.read(composerImagePickerProvider),
        service: mediaService,
        preparation: () => _controller.preparation,
        currentActor: () => ref.read(blogAccountIdProvider),
        isSessionCurrent: () =>
            mounted &&
            !_leaving &&
            {
              BlogEditorPhase.ready,
              BlogEditorPhase.failed,
            }.contains(_controller.value.phase),
        onUploaded: (image, _) => _body.insertImage(image.imageUri.toString()),
      )..addListener(_mediaChanged);
    }
    _controller.addListener(_syncInputs);
    ref.listenManual(blogAccountIdProvider, (_, actor) {
      if (actor != widget.target.actorUserId) {
        _drafts?.expire();
        _receipt = null;
        _body.expire();
        _media?.expire();
        _controller.expire();
      }
    });
    unawaited(_prepareEditor());
  }

  Future<void> _prepareEditor() async {
    if (_preparingEditor ||
        _leaving ||
        _controller.value.phase == BlogEditorPhase.expired) {
      return;
    }
    _preparingEditor = true;
    _restoringDraft = true;
    try {
      if (_drafts != null && !_drafts!.loaded && !await _drafts!.load()) return;
      if (!mounted || _leaving) return;
      await _controller.prepare();
      if (!mounted || _controller.value.phase != BlogEditorPhase.ready) return;
      if (!_didRestoreDraft) {
        _didRestoreDraft = true;
        final saved = _drafts?.snapshot;
        if (saved != null) {
          _creatingCategory = saved.creatingCategory;
          _controller.restoreDraft(restoreBlogDraft(saved));
          unawaited(
            _media?.restoreDraftImages([
                  for (final image in saved.images)
                    UserBlogDraftImageReference(
                      picId: image.picId,
                      originalUri: image.originalUri,
                    ),
                ]) ??
                Future.value(),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _controller.value.phase == BlogEditorPhase.expired) {
              return;
            }
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  saved.visibility == UserBlogVisibility.passwordProtected
                      ? l10n.profileBlogDraftPasswordRestored
                      : l10n.composerRestoredDraft,
                ),
              ),
            );
          });
        }
      }
    } finally {
      _restoringDraft = false;
      _preparingEditor = false;
      if (mounted) setState(() {});
    }
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  List<BlogDraftImage> _imageHints() => [
    for (final image in _media?.uploadedImages ?? <UserBlogUploadedImage>[])
      BlogDraftImage(picId: image.picId, originalUri: image.originalImageUri),
  ];

  void _saveDraftInput() {
    if (_resettingDraft ||
        _restoringDraft ||
        !{
          BlogEditorPhase.ready,
          BlogEditorPhase.failed,
        }.contains(_controller.value.phase)) {
      return;
    }
    _drafts?.update(
      _controller.value.draft,
      changed: _controller.value.dirty,
      creatingCategory: _creatingCategory,
      images: _imageHints(),
    );
  }

  bool get _imagesReady =>
      _media?.canPublish(_controller.value.draft.bodyHtml) ??
      (_drafts?.snapshot?.images.isEmpty ?? true);

  bool get _draftSettingsChanged {
    final options = _controller.value.options;
    if (_drafts?.snapshot == null || options == null) return false;
    final draft = _controller.value.draft;
    // Validate settings independently of an incomplete title or body.
    if (_creatingCategory && !options.canCreateCategory) return true;
    final issue = options.validateSettings(draft);
    return issue != null &&
        issue != BlogEditorIssue.passwordRequired &&
        issue != BlogEditorIssue.targetNamesRequired;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _drafts?.loaded == true) {
      unawaited(_drafts!.flush());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _scheduleFinish();
  }

  void _syncInputs() {
    final draft = _controller.value.draft;
    _body.load(draft.bodyHtml);
    for (final (controller, text) in [
      (_subject, draft.subject),
      (_tags, draft.tags),
      (_categoryName, draft.newPersonalCategory),
      (_password, draft.password),
      (_targetNames, draft.targetNames),
    ]) {
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    _saveDraftInput();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drafts?.removeListener(_draftChanged);
    _drafts?.dispose();
    _media?.removeListener(_mediaChanged);
    _media?.dispose();
    _body.dispose();
    _controller.removeListener(_syncInputs);
    _controller.dispose();
    _subject.dispose();
    _tags.dispose();
    _categoryName.dispose();
    _password.dispose();
    _targetNames.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_resettingDraft ||
        _media?.value.busy == true ||
        !_imagesReady ||
        _drafts?.pending == true) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (_creatingCategory && _categoryName.text.trim().isEmpty) {
      setState(() => _categoryNameRequired = true);
      await _openSettings();
      return;
    }
    final receipt = await _controller.submit(
      uploadedImages: _media?.uploadedImages ?? const [],
    );
    if (receipt != null) {
      final cleared = await _drafts?.complete();
      if (mounted && cleared == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).profileBlogDraftCleanupFailed,
            ),
          ),
        );
      }
    } else if (_drafts?.pending == true &&
        _controller.value.phase != BlogEditorPhase.unknown &&
        _controller.value.phase != BlogEditorPhase.expired &&
        _controller.value.phase != BlogEditorPhase.submitting) {
      await _drafts!.setPending(false);
    }
    if (!mounted || _leaving) return;
    if (receipt == null) {
      final issue = _controller.value.issue;
      if (issue != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_issueText(AppLocalizations.of(context), issue)),
          ),
        );
        if ({
          BlogEditorIssue.siteCategoryRequired,
          BlogEditorIssue.categoryUnavailable,
          BlogEditorIssue.newCategoryUnavailable,
          BlogEditorIssue.categoryConflict,
          BlogEditorIssue.feedUnavailable,
          BlogEditorIssue.passwordRequired,
          BlogEditorIssue.targetNamesRequired,
          BlogEditorIssue.visibilityUnavailable,
          BlogEditorIssue.commentsUnavailable,
        }.contains(issue)) {
          await _openSettings();
        }
      }
      return;
    }
    if (ref.read(blogAccountIdProvider) != widget.target.actorUserId) return;
    _receipt = receipt;
    ref.read(blogMutationBusProvider).publish(receipt);
    _scheduleFinish();
  }

  void _mediaChanged() {
    _saveDraftInput();
    if (mounted) setState(() {});
  }

  Future<void> _pickImages() async {
    _body.focusNode.unfocus();
    await _media?.pickImages();
    if (!mounted ||
        _leaving ||
        _controller.value.phase == BlogEditorPhase.expired) {
      return;
    }
    final failure = _media?.value.failure;
    if (failure != null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _media!.value.outcomeUnknown
                ? l10n.profileBlogImageUploadUnknown
                : LocalizedErrorSummary.resolve(l10n, failure),
          ),
        ),
      );
    }
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
    if (_drafts != null) {
      if (_closing || _dialogOpen) return;
      _closing = true;
      _media?.cancel();
      FocusScope.of(context).unfocus();
      final saved = !_drafts!.loaded || await _drafts!.flush();
      _closing = false;
      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).profileBlogDraftSaveFailed,
            ),
          ),
        );
        return;
      }
      if (_receipt != null) {
        _scheduleFinish();
        return;
      }
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
      return;
    }
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
    if (_drafts != null && !await _drafts!.flush()) return;
    if (!mounted) return;
    await openBlogWebPage(
      context,
      ref,
      expectedActor: widget.target.actorUserId,
      replaceCurrent: true,
      destination: (navigation) => navigation.editor(widget.target),
    );
  }

  void _changeDraft(BlogEditorDraft Function(BlogEditorDraft) change) {
    final draft = change(_controller.value.draft);
    if (_categoryNameRequired && draft.newPersonalCategory.trim().isNotEmpty) {
      setState(() => _categoryNameRequired = false);
    }
    _controller.update(draft);
    _saveDraftInput();
  }

  Future<void> _resetDraft() async {
    if (_resettingDraft) return;
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      title: l10n.composerResetDraftTitle,
      message: l10n.composerResetDraftBody,
      confirmKey: const Key('blog-draft-reset-confirm'),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _resettingDraft = true);
    final reset = await _drafts!.reset();
    if (!mounted) return;
    setState(() => _resettingDraft = false);
    if (!reset) return;
    _media?.reset();
    _creatingCategory = false;
    _categoryNameRequired = false;
    _controller.resetDraft();
    if (!_drafts!.loadFailed && _controller.value.options == null) {
      await _prepareEditor();
    }
    if (mounted) setState(() {});
  }

  Future<void> _resumeDraft() async {
    if (_controller.value.busy || _drafts?.pending != true) return;
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      title: l10n.profileBlogDraftResume,
      message: l10n.profileBlogDraftResumeConfirm,
      confirmKey: const Key('blog-draft-resume-confirm'),
    )) {
      return;
    }
    if (!mounted || !await _drafts!.setPending(false) || !mounted) {
      return;
    }
    await _controller.resumeAfterUnknown();
  }

  void _checkPublishedLogs() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            const ProfileBlogPage(initialScope: UserBlogFeedScope.self),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (_dialogOpen ||
        _controller.value.options == null ||
        _controller.value.busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    _dialogOpen = true;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).y300NativeContent.card,
      builder: (sheetContext) => ValueListenableBuilder<BlogEditorState>(
        valueListenable: _controller,
        builder: (context, state, _) {
          final l10n = AppLocalizations.of(context);
          // The sheet observes the same session as the page: expiring the editor
          // removes every old input here too, even while this route covers it.
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ComposerSettingsSheet(
              key: const Key('blog-editor-settings-sheet'),
              title: l10n.profileBlogPublishSettings,
              children: [
                if (state.options == null)
                  Text(l10n.forumWebViewAccountChanged)
                else
                  BlogEditorSettingsFields(
                    state: state,
                    locked: _resettingDraft || _drafts?.pending == true,
                    tags: _tags,
                    categoryName: _categoryName,
                    password: _password,
                    targetNames: _targetNames,
                    creatingCategory: _creatingCategory,
                    categoryNameRequired: _categoryNameRequired,
                    onCreateCategory: (value) => setState(() {
                      _creatingCategory = value;
                      _categoryNameRequired = false;
                    }),
                    onChanged: _changeDraft,
                  ),
                if ({
                  BlogEditorPhase.ready,
                  BlogEditorPhase.failed,
                }.contains(state.phase)) ...[
                  const Divider(height: 24),
                  ComposerSettingsActionTile(
                    tileKey: const Key('blog-editor-open-web'),
                    icon: Icons.open_in_browser_outlined,
                    title: l10n.profileBlogOpenWeb,
                    onPressed: () => Navigator.of(sheetContext).pop('web'),
                  ),
                  if (_drafts != null)
                    ComposerSettingsActionTile(
                      tileKey: const Key('blog-draft-reset'),
                      icon: Icons.restart_alt,
                      title: l10n.composerResetDraft,
                      onPressed: () => Navigator.of(sheetContext).pop('reset'),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    _scheduleFinish();
    if (action == 'web') await _openWeb();
    if (action == 'reset') await _resetDraft();
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
            _allowPop ||
            ((_drafts == null
                    ? !state.dirty
                    : state.phase == BlogEditorPhase.expired) &&
                _media?.value.busy != true &&
                state.phase != BlogEditorPhase.submitting &&
                state.phase != BlogEditorPhase.unknown),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _leaving = true;
          } else {
            unawaited(_confirmLeave());
          }
        },
        child: Scaffold(
          backgroundColor: native.card,
          appBar: AppBar(
            title: Text(
              creating ? l10n.profileBlogWrite : l10n.profileBlogEdit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (state.options != null)
                IconButton(
                  key: const Key('blog-editor-settings'),
                  tooltip: l10n.profileBlogPublishSettings,
                  style: composerAppBarActionStyle(context),
                  onPressed: state.busy ? null : _openSettings,
                  icon: const Icon(Icons.tune),
                ),
              if (state.options != null)
                IconButton(
                  key: const Key('blog-editor-preview-toggle'),
                  style: composerAppBarActionStyle(context),
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
                style: composerAppBarActionStyle(context),
                tooltip: creating ? l10n.profileBlogPublish : l10n.commonSave,
                onPressed:
                    state.canSubmit &&
                        !_resettingDraft &&
                        _media?.value.busy != true &&
                        _imagesReady &&
                        _drafts?.pending != true
                    ? _submit
                    : null,
                icon: Icon(creating ? Icons.send : Icons.check),
              ),
            ],
          ),
          bottomNavigationBar: state.options != null && !_preview
              ? Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: BlogRichTextToolbar(
                    controller: _body,
                    enabled:
                        !state.busy &&
                        !_resettingDraft &&
                        _drafts?.pending != true &&
                        _media?.value.busy != true &&
                        {
                          BlogEditorPhase.ready,
                          BlogEditorPhase.failed,
                        }.contains(state.phase),
                    smilies: _controller.preparation?.blogSmilies ?? const [],
                    onImagePressed:
                        _media != null &&
                            _controller.preparation?.imageUploadLimits != null
                        ? _pickImages
                        : null,
                  ),
                )
              : null,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                key: const Key('blog-editor-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_drafts != null && state.phase != BlogEditorPhase.expired)
                    BlogDraftStatus(
                      loadFailed: _drafts!.loadFailed,
                      saveFailed: _drafts!.saveFailed,
                      pending: _drafts!.pending && !state.busy,
                      imagesBlocked: !_imagesReady,
                      verifyingImages: _media?.value.verifyingDraft == true,
                      onLoadRetry: _prepareEditor,
                      onSaveRetry: () => unawaited(_drafts!.flush()),
                      onImageRetry: _media?.retryDraftImages,
                      onCheck: _checkPublishedLogs,
                      onResume: _resumeDraft,
                    ),
                  if (_drafts?.loadFailed == true)
                    TextButton(
                      key: const Key('blog-draft-reset-load-error'),
                      onPressed: _resetDraft,
                      child: Text(l10n.composerResetDraft),
                    ),
                  if (_draftSettingsChanged) ...[
                    Text(
                      l10n.profileBlogDraftSettingsChanged,
                      key: const Key('blog-draft-settings-changed'),
                      style: TextStyle(color: native.supportingText),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_media?.value.busy == true) ...[
                    LinearProgressIndicator(
                      value: _media!.value.total == 0
                          ? null
                          : ((_media!.value.current - 1) +
                                    _media!.value.progress) /
                                _media!.value.total,
                    ),
                    const SizedBox(height: 8),
                  ],
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
                            : LocalizedErrorSummary.resolve(
                                l10n,
                                state.failure,
                              ),
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
                        locked: _resettingDraft || _drafts?.pending == true,
                        subject: _subject,
                        creatingCategory: _creatingCategory,
                        bodyController: _body,
                        mediaBusy: _media?.value.busy == true,
                        imagePreviews: _media?.previewPaths ?? const {},
                        bodyMinLines:
                            ((constraints.maxHeight - 240) /
                                    (MediaQuery.textScalerOf(
                                          context,
                                        ).scale(16) *
                                        1.6))
                                .floor()
                                .clamp(4, 24),
                        onChanged: _changeDraft,
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
                      if (state.phase == BlogEditorPhase.failed &&
                          state.options == null)
                        TextButton(
                          key: const Key('blog-editor-open-web'),
                          onPressed: _openWeb,
                          child: Text(l10n.profileBlogOpenWeb),
                        ),
                      if (state.phase == BlogEditorPhase.failed)
                        FilledButton(
                          key: const Key('blog-editor-retry'),
                          onPressed: _prepareEditor,
                          child: Text(l10n.commonRetry),
                        ),
                    ],
                  ),
                ],
              ),
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
  BlogEditorIssue.passwordRequired => l10n.profileBlogPasswordRequired,
  BlogEditorIssue.targetNamesRequired => l10n.profileBlogTargetNamesRequired,
  BlogEditorIssue.visibilityUnavailable =>
    l10n.profileBlogVisibilityUnavailable,
  BlogEditorIssue.commentsUnavailable => l10n.profileBlogCommentsUnavailable,
  BlogEditorIssue.serverChanged => l10n.profileBlogServerChanged,
};
