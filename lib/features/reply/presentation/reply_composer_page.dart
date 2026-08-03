import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_message_editor_surface.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_error_summary.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_draft_attachment_preview_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

class ReplyComposerPage extends ConsumerStatefulWidget {
  const ReplyComposerPage({super.key, required this.args});

  final ReplyComposerArgs args;

  @override
  ConsumerState<ReplyComposerPage> createState() => _ReplyComposerPageState();
}

class _ReplyComposerPageState extends ConsumerState<ReplyComposerPage> {
  late final TextEditingController _messageController;
  ReplyComposerController? _controller;
  ComposerSurfacePreference _editorSurface = ComposerSurfacePreference.quill;
  bool _didApplySurfacePreference = false;
  bool _didApplyRestoredDraft = false;
  bool _didNotifyRestoredDraft = false;
  bool _allowPopWithoutConfirm = false;
  String? _lastAppliedStateMessage;
  Object? _lastNotifiedDraftImageVerification;
  final ComposerUploadFeedbackTracker _uploadFeedbackTracker =
      ComposerUploadFeedbackTracker();

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.flushDraft());
    }
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = replyComposerControllerProvider(widget.args);
    final asyncState = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final bbCodeRenderer = ref.watch(forumBbCodeRendererProvider);
    final stickerGroups = ref
        .watch(stickerGroupsProvider)
        .maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    final composerPreferences = ref.watch(
      composerPreferencesControllerProvider,
    );
    if (!_didApplySurfacePreference && composerPreferences.hasValue) {
      _didApplySurfacePreference = true;
      _editorSurface = composerPreferences.value!.defaultSurface;
    }
    final lastStickerGroupId = ref
        .watch(stickerPickerLastGroupIdControllerProvider)
        .value;
    _controller = controller;
    final state = asyncState.value;
    if (state != null) {
      _syncMessageController(state);
      _scheduleTransientFeedback(state);
    }

    return PopScope(
      canPop: !_shouldConfirmPop(state),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_confirmAndPop(context, controller));
      },
      child: Scaffold(
        resizeToAvoidBottomInset:
            _editorSurface != ComposerSurfacePreference.quill,
        appBar: AppBar(
          title: Text(
            widget.args.target.isPostReply
                ? l10n.replyFloorTitle
                : l10n.replyThreadTitle,
          ),
          actions: [
            IconButton(
              key: const Key('reply-composer-source-button'),
              tooltip: _editorSurface == ComposerSurfacePreference.quill
                  ? l10n.composerSourceMode
                  : l10n.composerVisualMode,
              onPressed: state == null
                  ? null
                  : () {
                      _toggleEditorSurface(state);
                    },
              style: composerAppBarActionStyle(context),
              icon: Icon(
                _editorSurface == ComposerSurfacePreference.quill
                    ? Icons.code
                    : Icons.edit_outlined,
              ),
            ),
            IconButton(
              key: const Key('reply-composer-more-button'),
              tooltip: l10n.composerMore,
              onPressed: state == null
                  ? null
                  : () {
                      _showSettingsSheet();
                    },
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.more_vert),
            ),
            IconButton(
              key: const Key('reply-composer-send-button'),
              tooltip: l10n.replySubmit,
              onPressed: state == null || !state.canSubmit
                  ? null
                  : () {
                      unawaited(_submit(context, controller));
                    },
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ComposerLoadErrorView(
            message: l10n.composerLoadDraftFailed(
              ComposerErrorSummary.sanitize(error) ??
                  l10n.composerUnknownFailure('other'),
            ),
            textKey: const Key('reply-composer-load-error'),
          ),
          data: (state) => _ReplyComposerBody(
            state: state,
            bbCodeRenderer: bbCodeRenderer,
            stickerGroups: stickerGroups,
            messageController: _messageController,
            editorSurface: _editorSurface,
            initialStickerGroupId: lastStickerGroupId,
            onStickerGroupChanged: (groupId) {
              unawaited(
                ref
                    .read(stickerPickerLastGroupIdControllerProvider.notifier)
                    .selectGroup(groupId),
              );
            },
            onMessageChanged: (value) {
              _lastAppliedStateMessage = value;
              controller.updateMessage(value);
            },
            onRetryPrepare: controller.retryPreparePostReply,
            onRetryDraftImages: controller.retryDraftAttachmentVerification,
            onImagePressed: (anchor) {
              if (state.pendingAttachmentAids.isNotEmpty) {
                if (anchor == null) {
                  return Future<void>.value();
                }
                return controller.insertPendingAttachments(anchor);
              }
              return controller.pickImages(insertionAnchor: anchor);
            },
          ),
        ),
      ),
    );
  }

  void _toggleEditorSurface(ReplyComposerState state) {
    final previous = _editorSurface;
    final next = previous == ComposerSurfacePreference.quill
        ? ComposerSurfacePreference.source
        : ComposerSurfacePreference.quill;
    setState(() {
      if (previous == ComposerSurfacePreference.quill) {
        _messageController.text = state.message;
        _lastAppliedStateMessage = state.message;
      }
      _editorSurface = next;
    });
    unawaited(_persistEditorSurface(previous: previous, next: next));
  }

  Future<void> _persistEditorSurface({
    required ComposerSurfacePreference previous,
    required ComposerSurfacePreference next,
  }) async {
    try {
      await ref
          .read(composerPreferencesControllerProvider.notifier)
          .setDefaultSurface(next);
    } catch (_) {
      if (mounted && _editorSurface == next) {
        setState(() => _editorSurface = previous);
      }
    }
  }

  void _syncMessageController(ReplyComposerState state) {
    final selection = _selectionForMessage(state);
    if (_didApplyRestoredDraft) {
      if (_lastAppliedStateMessage == state.message ||
          _messageController.text == state.message) {
        _lastAppliedStateMessage = state.message;
        return;
      }
      _messageController.value = TextEditingValue(
        text: state.message,
        selection: selection,
      );
      _lastAppliedStateMessage = state.message;
      return;
    }
    _didApplyRestoredDraft = true;
    _messageController.value = TextEditingValue(
      text: state.message,
      selection: TextSelection.collapsed(offset: state.message.length),
    );
    _lastAppliedStateMessage = state.message;
  }

  TextSelection _selectionForMessage(ReplyComposerState state) {
    final mutation = state.lastMessageMutation;
    if (mutation != null && mutation.revision == state.messageRevision) {
      final offset = mutation.resultSelection.start
          .clamp(0, state.message.length)
          .toInt();
      return TextSelection.collapsed(offset: offset);
    }
    return TextSelection.collapsed(offset: state.message.length);
  }

  void _scheduleTransientFeedback(ReplyComposerState state) {
    final l10n = AppLocalizations.of(context);
    final verification = state.draftAttachmentVerification;
    final shouldNotifyInvalidDraftImages =
        verification.invalidAidCount > 0 &&
        !identical(_lastNotifiedDraftImageVerification, verification);
    if (shouldNotifyInvalidDraftImages) {
      _lastNotifiedDraftImageVerification = verification;
    }
    final shouldNotifyRestoredDraft =
        state.restoredDraft && !_didNotifyRestoredDraft;
    if (shouldNotifyRestoredDraft) {
      _didNotifyRestoredDraft = true;
    }
    final messages = <String>[
      if (shouldNotifyRestoredDraft) l10n.composerRestoredDraft,
      if (shouldNotifyInvalidDraftImages)
        l10n.composerDraftImagesInvalidated(verification.invalidAidCount),
      ..._uploadFeedbackTracker
          .update(state)
          .map(
            (feedback) => ComposerTextResolver.uploadFeedback(l10n, feedback),
          ),
    ];
    if (messages.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showComposerSnackBar(
        context,
        messages.join('\n'),
        snackBarKey: shouldNotifyInvalidDraftImages
            ? const Key('reply-composer-invalid-draft-images-snackbar')
            : null,
      );
    });
  }

  Future<void> _submit(
    BuildContext context,
    ReplyComposerController controller,
  ) async {
    final navigator = Navigator.of(context);
    final result = await controller.submit();
    if (!mounted || !result.sent) {
      return;
    }
    _allowPopWithoutConfirm = true;
    navigator.pop(result);
  }

  bool _shouldConfirmPop(ReplyComposerState? state) {
    if (_allowPopWithoutConfirm) {
      return false;
    }
    return state != null &&
        (state.message.trim().isNotEmpty || state.imageAttachments.isNotEmpty);
  }

  Future<void> _confirmAndPop(
    BuildContext context,
    ReplyComposerController controller,
  ) async {
    final navigator = Navigator.of(context);
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.replyLeaveTitle),
          content: Text(l10n.replyLeaveBody),
          actions: [
            TextButton(
              key: const Key('reply-composer-continue-edit-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(l10n.composerContinueEditing),
            ),
            FilledButton(
              key: const Key('reply-composer-save-leave-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(l10n.composerSaveDraftAndLeave),
            ),
          ],
        );
      },
    );
    if (!mounted || shouldLeave != true) {
      return;
    }
    await controller.flushDraft();
    if (!mounted) {
      return;
    }
    _allowPopWithoutConfirm = true;
    navigator.pop();
  }

  void _showSettingsSheet() {
    final provider = replyComposerControllerProvider(widget.args);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            final sheetState = ref.watch(provider).value;
            final enabled =
                sheetState != null &&
                !sheetState.isSubmitting &&
                !sheetState.isPreparing;
            final canReset =
                sheetState != null &&
                !sheetState.isSubmitting &&
                sheetState.hasDraftContent;
            final notifier = ref.read(provider.notifier);
            return ComposerSettingsSheet(
              key: const Key('reply-composer-settings-sheet'),
              title: l10n.composerMoreSettings,
              children: [
                ComposerSettingsSwitchTile(
                  tileKey: const Key('reply-composer-use-signature-switch'),
                  title: l10n.composerUseSignature,
                  value: sheetState?.useSignature ?? false,
                  onChanged: notifier.toggleUseSignature,
                  enabled: enabled,
                ),
                const Divider(),
                ComposerSettingsActionTile(
                  tileKey: const Key('reply-composer-reset-draft-button'),
                  icon: Icons.restart_alt,
                  title: l10n.composerResetDraft,
                  destructive: true,
                  onPressed: canReset
                      ? () {
                          Navigator.of(sheetContext).pop();
                          unawaited(_confirmResetDraft(notifier));
                        }
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmResetDraft(ReplyComposerController controller) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.composerResetDraftTitle),
          content: Text(l10n.composerResetDraftBody),
          actions: [
            TextButton(
              key: const Key('reply-composer-reset-cancel-button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const Key('reply-composer-reset-confirm-button'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonReset),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    await controller.resetDraft();
  }
}

class _ReplyComposerBody extends StatelessWidget {
  const _ReplyComposerBody({
    required this.state,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.messageController,
    required this.editorSurface,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    required this.onRetryPrepare,
    required this.onRetryDraftImages,
    required this.onImagePressed,
  });

  final ReplyComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final TextEditingController messageController;
  final ComposerSurfacePreference editorSurface;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final VoidCallback onRetryPrepare;
  final Future<void> Function() onRetryDraftImages;
  final ComposerImageInsertCallback onImagePressed;

  @override
  Widget build(BuildContext context) {
    final editor = ComposerMessageEditorSurface(
      surface: editorSurface,
      message: state.message,
      sourceController: messageController,
      enabled: !state.isSubmitting && !state.isPreparing,
      bbCodeRenderer: bbCodeRenderer,
      stickerGroups: stickerGroups,
      stickers: [for (final group in stickerGroups) ...group.stickers],
      initialStickerGroupId: initialStickerGroupId,
      onStickerGroupChanged: onStickerGroupChanged,
      onMessageChanged: onMessageChanged,
      onImagePressed: onImagePressed,
      imageAttachments: state.imageAttachments,
      attachmentResolver: ComposerDraftAttachmentPreviewResolver(
        imageAttachments: state.imageAttachments,
        verification: state.draftAttachmentVerification,
      ),
      keyPrefix: 'reply-composer',
      hintText: AppLocalizations.of(context).replyMessageHint,
      messageRevision: state.messageRevision,
      lastMessageMutation: state.lastMessageMutation,
      isUploadingImages: state.isUploadingImages,
      imageUploadCurrent: state.imageUploadCurrent,
      imageUploadTotal: state.imageUploadTotal,
    );
    final topFeedback = _buildFeedbackWidgets(context);
    if (editorSurface == ComposerSurfacePreference.quill) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topFeedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ForumContentSpacing.composerPageHorizontal,
                  ForumContentSpacing.composerPageVertical,
                  ForumContentSpacing.composerPageHorizontal,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: topFeedback,
                ),
              ),
            Expanded(child: editor),
          ],
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: ForumContentSpacing.composerPageHorizontal,
          vertical: ForumContentSpacing.composerPageVertical,
        ),
        children: [
          ..._buildLeadingFeedbackWidgets(context),
          editor,
          ..._buildTrailingFeedbackWidgets(context),
        ],
      ),
    );
  }

  List<Widget> _buildFeedbackWidgets(BuildContext context) {
    return [
      ..._buildLeadingFeedbackWidgets(context),
      ..._buildTrailingFeedbackWidgets(context),
    ];
  }

  List<Widget> _buildLeadingFeedbackWidgets(BuildContext context) {
    final verification = state.draftAttachmentVerification;
    return [
      if (verification.failed) ...[
        ComposerStatusBanner.error(
          key: const Key('reply-composer-draft-image-verification-error'),
          text: AppLocalizations.of(
            context,
          ).composerDraftImageVerificationFailed,
          retryButtonKey: const Key(
            'reply-composer-retry-draft-image-verification',
          ),
          onRetry: () {
            unawaited(onRetryDraftImages());
          },
        ),
        const SizedBox(height: 12),
      ],
      if (state.pendingAttachmentNotice case final notice?) ...[
        ComposerStatusBanner.info(
          key: const Key('reply-composer-pending-attachment'),
          text: ComposerTextResolver.pendingAttachment(
            AppLocalizations.of(context),
            notice,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
      ],
      if (state.target.isPostReply) ...[
        _ReplyReferenceStatus(state: state, onRetryPrepare: onRetryPrepare),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildTrailingFeedbackWidgets(BuildContext context) {
    return [
      if (state.failure case final failure?) ...[
        const SizedBox(height: 8),
        Text(
          ComposerTextResolver.failure(AppLocalizations.of(context), failure),
          key: const Key('reply-composer-error-message'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }
}

class _ReplyReferenceStatus extends StatelessWidget {
  const _ReplyReferenceStatus({
    required this.state,
    required this.onRetryPrepare,
  });

  final ReplyComposerState state;
  final VoidCallback onRetryPrepare;

  @override
  Widget build(BuildContext context) {
    if (state.isPreparing) {
      return ComposerStatusBanner.loading(
        text: AppLocalizations.of(context).replyPreparingQuote,
      );
    }

    final failure = state.preparationFailure;
    if (failure != null) {
      return ComposerStatusBanner.error(
        key: const Key('reply-composer-preparation-error'),
        text: ComposerTextResolver.operationFailure(
          AppLocalizations.of(context),
          failure,
        ),
        retryButtonKey: const Key('reply-composer-retry-prepare-button'),
        onRetry: onRetryPrepare,
      );
    }

    final reference = state.preparation?.reference;
    final noticeAuthorMsg = reference?.noticeAuthorMsg?.trim();
    final rawQuotePreview = reference?.rawQuotePreview?.trim();
    final preview = noticeAuthorMsg != null && noticeAuthorMsg.isNotEmpty
        ? noticeAuthorMsg
        : rawQuotePreview;
    if (preview == null || preview.isEmpty) {
      return const SizedBox.shrink();
    }
    return ComposerStatusBanner.info(
      text: preview,
      textKey: const Key('reply-composer-reference-banner'),
      maxLines: 3,
    );
  }
}
