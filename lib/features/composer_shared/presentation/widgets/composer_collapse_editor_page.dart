import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_insertion_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_revision_tracker.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_collapse_editor_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_title_field_decoration.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

typedef ComposerCollapseSaveCommitter =
    Future<ComposerCollapseCommitStatus> Function(ComposerCollapseDraft draft);
typedef ComposerCollapseDeleteCommitter =
    Future<ComposerCollapseCommitStatus> Function();

/// Full-screen editor for one atomic collapse embed.
///
/// The parent document stays untouched until a save/delete committer succeeds.
/// Nested collapse markup is decoded as read-only atomic previews because the
/// body surface deliberately disables collapse creation and drill-down edits.
class ComposerCollapseEditorPage extends StatefulWidget {
  const ComposerCollapseEditorPage({
    super.key,
    required this.isNew,
    required this.initialDraft,
    required this.hostController,
    required this.bodyCapabilities,
    required this.onSave,
    required this.collapseRenderer,
    this.onDelete,
    this.onImagePressed,
    this.stickers = const <StickerItem>[],
    this.stickerGroups = const <StickerGroup>[],
    this.initialStickerGroupId,
    this.onStickerGroupChanged,
    this.extraToolbarActions = const <ComposerToolbarAction>[],
    this.attachImageBuilder,
    this.attachFileExists,
    this.keyPrefix = 'composer-collapse-editor',
  });

  final bool isNew;
  final ComposerCollapseDraft initialDraft;
  final ComposerCollapseEditorHostController hostController;
  final ComposerQuillCapabilities bodyCapabilities;
  final ComposerCollapseSaveCommitter onSave;
  final ComposerCollapseDeleteCommitter? onDelete;
  final ComposerImageInsertCallback? onImagePressed;
  final List<StickerItem> stickers;
  final List<StickerGroup> stickerGroups;
  final String? initialStickerGroupId;
  final ValueChanged<String>? onStickerGroupChanged;
  final ForumBbCodeRenderer collapseRenderer;
  final List<ComposerToolbarAction> extraToolbarActions;
  final ForumAttachPreviewImageBuilder? attachImageBuilder;
  final ForumAttachPreviewFileExists? attachFileExists;
  final String keyPrefix;

  @override
  State<ComposerCollapseEditorPage> createState() =>
      _ComposerCollapseEditorPageState();
}

class _ComposerCollapseEditorPageState
    extends State<ComposerCollapseEditorPage> {
  static const _codec = ComposerQuillBbCodeCodec();
  static const _insertionService = ComposerMessageInsertionService();

  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final QuillController _bodyController;
  late final ComposerMessageRevisionTracker _bodyRevisionTracker;
  late final int _hostGeneration;
  late String _bodyBbCode;
  ComposerTextMutation? _lastBodyMutation;
  bool _allowPop = false;
  bool _isCommitting = false;
  bool _isShowingDiscardDialog = false;
  bool _isImageRequestInFlight = false;
  bool _sawHostUpload = false;
  int _localGeneration = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialDraft.title)
      ..addListener(_handleTitleChanged);
    _titleFocusNode = FocusNode();
    _bodyBbCode = widget.initialDraft.bodyBbCode;
    _bodyRevisionTracker = ComposerMessageRevisionTracker(
      initialSource: _bodyBbCode,
    );
    _hostGeneration = widget.hostController.value.documentGeneration;
    final document = _codec.decodeDocument(_bodyBbCode);
    _bodyController = QuillController(
      document: document,
      selection: TextSelection.collapsed(
        offset: (document.length - 1).clamp(0, document.length).toInt(),
      ),
    );
    widget.hostController.addListener(_handleHostChanged);
  }

  @override
  void dispose() {
    _localGeneration += 1;
    widget.hostController.removeListener(_handleHostChanged);
    _titleController
      ..removeListener(_handleTitleChanged)
      ..dispose();
    _titleFocusNode.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _titleController.text != widget.initialDraft.title ||
      _bodyBbCode != widget.initialDraft.bodyBbCode;

  bool get _isUploadBlocking =>
      _isImageRequestInFlight || widget.hostController.value.isUploadingImages;

  bool get _isExitBlocking => _isUploadBlocking || _isCommitting;

  bool get _canMutateParent =>
      widget.hostController.isActive &&
      widget.hostController.value.enabled &&
      !_isUploadBlocking &&
      !_isCommitting;

  bool get _canSave => _canMutateParent && (widget.isNew || _isDirty);

  void _handleTitleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleHostChanged() {
    final uploading = widget.hostController.value.isUploadingImages;
    if (uploading) {
      _sawHostUpload = true;
    } else if (_sawHostUpload) {
      _sawHostUpload = false;
      _isImageRequestInFlight = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _handleBodyChanged(String next) {
    if (next == _bodyBbCode) {
      return;
    }
    final previous = _bodyBbCode;
    _bodyRevisionTracker.recordChange(
      previousSource: previous,
      nextSource: next,
    );
    setState(() {
      _bodyBbCode = next;
      _lastBodyMutation = null;
    });
  }

  ComposerLocalAttachmentInsertion _buildLocalAttachmentInsertion({
    required ComposerSelection selection,
    required int baseRevision,
  }) {
    final generation = _localGeneration;
    return (codes) {
      if (!mounted ||
          !widget.hostController.isActive ||
          widget.hostController.value.documentGeneration != _hostGeneration ||
          generation != _localGeneration) {
        return ComposerLocalAttachmentInsertionResult.stale;
      }
      final resolved = _bodyRevisionTracker.resolve(
        ComposerInsertionAnchor(
          baseRevision: baseRevision,
          selection: selection,
          mode: ComposerEditorMode.quill,
        ),
      );
      if (resolved == null) {
        return ComposerLocalAttachmentInsertionResult.stale;
      }
      final mutation = _insertionService.insertAttachmentBlock(
        source: _bodyBbCode,
        selection: resolved.selection,
        attachmentCodes: codes,
        revision: _bodyRevisionTracker.revision + 1,
      );
      _bodyRevisionTracker.recordChange(
        previousSource: _bodyBbCode,
        nextSource: mutation.nextSource,
      );
      final appliedMutation = ComposerTextMutation(
        previousSource: mutation.previousSource,
        nextSource: mutation.nextSource,
        replacedSelection: mutation.replacedSelection,
        resultSelection: mutation.resultSelection,
        revision: _bodyRevisionTracker.revision,
      );
      setState(() {
        _bodyBbCode = mutation.nextSource;
        _lastBodyMutation = appliedMutation;
      });
      return ComposerLocalAttachmentInsertionResult.applied;
    };
  }

  Future<void> _handleImagePressed(ComposerInsertionAnchor? anchor) async {
    final callback = widget.onImagePressed;
    if (callback == null || _isUploadBlocking || !_canMutateParent) {
      return;
    }
    setState(() {
      _isImageRequestInFlight = true;
      _sawHostUpload = false;
    });
    try {
      await callback(anchor);
    } finally {
      _settleImageRequestAfterPicker(remainingFrames: 2);
    }
  }

  void _settleImageRequestAfterPicker({required int remainingFrames}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.hostController.value.isUploadingImages ||
          _sawHostUpload) {
        return;
      }
      if (remainingFrames > 0) {
        _settleImageRequestAfterPicker(remainingFrames: remainingFrames - 1);
        return;
      }
      setState(() => _isImageRequestInFlight = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final host = widget.hostController.value;
    final editorEnabled =
        widget.hostController.isActive && host.enabled && !_isCommitting;
    return PopScope(
      canPop: _allowPop || (!_isDirty && !_isExitBlocking),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_isCommitting) {
          return;
        }
        if (_isUploadBlocking) {
          _showUploadStatus();
          return;
        }
        unawaited(_confirmDiscardAndPop());
      },
      child: Scaffold(
        key: Key('${widget.keyPrefix}-page'),
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: BackButton(onPressed: _handleBackPressed),
          title: Text(
            widget.isNew
                ? localizations.composerCollapseCreateTitle
                : localizations.composerCollapseEditTitle,
          ),
          actions: [
            if (widget.onDelete != null)
              IconButton(
                key: Key('${widget.keyPrefix}-delete-button'),
                tooltip: localizations.commonDelete,
                onPressed: _canMutateParent ? _confirmDelete : null,
                style: composerAppBarActionStyle(context),
                icon: const Icon(Icons.delete_outline),
              ),
            IconButton(
              key: Key('${widget.keyPrefix}-save-button'),
              tooltip: localizations.commonSave,
              onPressed: _canSave ? _save : null,
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Column(
          key: Key('${widget.keyPrefix}-content-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: Key('${widget.keyPrefix}-title-padding'),
              padding: const EdgeInsets.fromLTRB(
                ForumContentSpacing.composerPageHorizontal,
                ForumContentSpacing.composerPageVertical,
                ForumContentSpacing.composerPageHorizontal,
                12,
              ),
              child: TextField(
                key: Key('${widget.keyPrefix}-title-field'),
                controller: _titleController,
                focusNode: _titleFocusNode,
                enabled: editorEnabled,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                decoration: composerTitleFieldDecoration(
                  context,
                  hintText: localizations.composerCollapseTitleHint,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\]\r\n\uFFFC]')),
                ],
              ),
            ),
            if (_isUploadBlocking)
              _CollapseUploadStatus(
                current: host.imageUploadCurrent,
                total: host.imageUploadTotal,
              ),
            Expanded(
              child: ComposerQuillEditorSurface(
                key: Key('${widget.keyPrefix}-body-surface'),
                keyPrefix: '${widget.keyPrefix}-body',
                controller: _bodyController,
                bbCode: _bodyBbCode,
                enabled: editorEnabled,
                expand: true,
                minHeight: 160,
                hintText: localizations.composerCollapseBodyHint,
                capabilities: widget.bodyCapabilities,
                messageRevision: _bodyRevisionTracker.revision,
                lastMessageMutation: _lastBodyMutation,
                onBbCodeChanged: _handleBodyChanged,
                onImagePressed: widget.onImagePressed == null
                    ? null
                    : _handleImagePressed,
                localAttachmentInsertionBuilder: _buildLocalAttachmentInsertion,
                stickers: widget.stickers,
                stickerGroups: widget.stickerGroups,
                initialStickerGroupId: widget.initialStickerGroupId,
                onStickerGroupChanged: widget.onStickerGroupChanged,
                imageAttachments: host.imageAttachments,
                attachmentResolver: host.attachmentResolver,
                collapseRenderer: widget.collapseRenderer,
                isUploadingImages: host.isUploadingImages,
                imageUploadCurrent: host.imageUploadCurrent,
                imageUploadTotal: host.imageUploadTotal,
                extraToolbarActions: widget.extraToolbarActions,
                attachImageBuilder: widget.attachImageBuilder,
                attachFileExists: widget.attachFileExists,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadStatus() {
    final host = widget.hostController.value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).composerUploadingImages(
            host.imageUploadCurrent,
            host.imageUploadTotal,
          ),
        ),
      ),
    );
  }

  void _handleBackPressed() {
    if (_isCommitting) {
      return;
    }
    if (_isUploadBlocking) {
      _showUploadStatus();
      return;
    }
    if (_isDirty) {
      unawaited(_confirmDiscardAndPop());
      return;
    }
    _closePage(Navigator.of(context));
  }

  Future<void> _save() async {
    if (!_canSave) {
      return;
    }
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _isCommitting = true);
    final result = await widget.onSave(
      ComposerCollapseDraft(
        title: _titleController.text,
        bodyBbCode: _bodyBbCode,
      ),
    );
    if (!mounted) {
      return;
    }
    if (result == ComposerCollapseCommitStatus.applied) {
      _closePage(navigator);
      return;
    }
    setState(() => _isCommitting = false);
    _showConflict();
  }

  Future<void> _confirmDelete() async {
    final committer = widget.onDelete;
    if (committer == null || !_canMutateParent) {
      return;
    }
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final localizations = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(localizations.composerCollapseDeleteTitle),
          content: Text(localizations.composerCollapseDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(localizations.commonCancel),
            ),
            FilledButton(
              key: Key('${widget.keyPrefix}-delete-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(localizations.commonDelete),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true || !_canMutateParent) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isCommitting = true);
    final result = await committer();
    if (!mounted) {
      return;
    }
    if (result == ComposerCollapseCommitStatus.applied) {
      _closePage(navigator);
      return;
    }
    setState(() => _isCommitting = false);
    _showConflict();
  }

  Future<void> _confirmDiscardAndPop() async {
    if (_isShowingDiscardDialog || _isUploadBlocking) {
      return;
    }
    _isShowingDiscardDialog = true;
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final localizations = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(localizations.composerCollapseDiscardTitle),
          content: Text(localizations.composerCollapseDiscardBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(localizations.commonCancel),
            ),
            FilledButton(
              key: Key('${widget.keyPrefix}-discard-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(localizations.composerCollapseDiscardConfirm),
            ),
          ],
        );
      },
    );
    if (!mounted) {
      return;
    }
    _isShowingDiscardDialog = false;
    if (discard == true) {
      if (_isUploadBlocking) {
        _showUploadStatus();
        return;
      }
      _closePage(navigator);
    }
  }

  void _closePage(NavigatorState navigator) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        navigator.pop();
      }
    });
  }

  void _showConflict() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).composerCollapseConflict),
      ),
    );
  }
}

class _CollapseUploadStatus extends StatelessWidget {
  const _CollapseUploadStatus({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final safeTotal = total > 0 ? total : 1;
    final progress = (current / safeTotal).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(
              context,
            ).composerUploadingImages(current, total),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: total > 0 ? progress : null),
        ],
      ),
    );
  }
}
