import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_message_editor_surface.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_toolbar_action.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/features/thread/presentation/widgets/post_edit_attachment_panel.dart';
import 'package:y300/features/posting/presentation/widgets/thread_subject_field.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

class PostEditComposerPage extends ConsumerStatefulWidget {
  const PostEditComposerPage({super.key, required this.args});

  final PostEditComposerArgs args;

  @override
  ConsumerState<PostEditComposerPage> createState() =>
      _PostEditComposerPageState();
}

class _PostEditComposerPageState extends ConsumerState<PostEditComposerPage> {
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  bool _didApplySubject = false;
  bool _didApplyMessage = false;
  bool _allowRoutePop = false;
  String? _lastAppliedSubject;
  String? _lastAppliedMessage;

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = postEditComposerControllerProvider(widget.args);
    final asyncState = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final state = asyncState.value;
    final stickerGroups = ref
        .watch(stickerGroupsProvider)
        .maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    final lastStickerGroupId = ref
        .watch(stickerPickerLastGroupIdControllerProvider)
        .value;
    if (state != null) {
      _syncSubjectController(state);
      _syncMessageController(state);
    }

    final needsStructuredDismissResult =
        state?.mayHaveServerMutationOnExit ?? false;
    return PopScope(
      canPop: _allowRoutePop || !needsStructuredDismissResult,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _popDismissed(state);
        }
      },
      child: Scaffold(
        key: const Key('post-edit-composer-page'),
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(l10n.postEditTitle),
          actions: [
            IconButton(
              key: const Key('post-edit-switch-webview-button'),
              tooltip: l10n.postEditSwitchToWebView,
              onPressed: state == null ? null : () => _openWebView(controller),
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.swap_horiz),
            ),
            IconButton(
              key: const Key('post-edit-save-button'),
              tooltip: l10n.postEditSave,
              onPressed: state?.canSubmit == true
                  ? () => unawaited(_submit(controller))
                  : null,
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ComposerLoadErrorView(
            message: l10n.postEditLoadFailed(error.toString()),
            textKey: const Key('post-edit-load-error'),
          ),
          data: (value) => _PostEditComposerBody(
            state: value,
            subjectController: _subjectController,
            messageController: _messageController,
            bbCodeRenderer: ref.watch(forumBbCodeRendererProvider),
            stickerGroups: stickerGroups,
            initialStickerGroupId: lastStickerGroupId,
            onStickerGroupChanged: (groupId) {
              unawaited(
                ref
                    .read(stickerPickerLastGroupIdControllerProvider.notifier)
                    .selectGroup(groupId),
              );
            },
            onMessageChanged: controller.updateMessage,
            onSubjectChanged: controller.updateSubject,
            attachmentResolver: controller.attachmentResolver(value),
            attachmentPanelBuilder: (_) {
              return Consumer(
                builder: (context, panelRef, _) {
                  final panelState = panelRef.watch(provider).value ?? value;
                  final panelController = panelRef.read(provider.notifier);
                  return PostEditAttachmentPanel(
                    key: const Key('post-edit-attachment-panel'),
                    state: panelState,
                    resolver: panelController.attachmentResolver(panelState),
                    onDeleteImage: panelController.deleteImage,
                  );
                },
              );
            },
            onImagePressed: (anchor) {
              return controller.pickImages(insertionAnchor: anchor);
            },
            onUseServerVersion: controller.useServerVersion,
            onKeepLocalVersion: controller.keepLocalVersion,
            onRetryVerification: () {
              return state?.submitState == PostEditSubmitState.unconfirmed
                  ? controller.retrySubmitVerification()
                  : controller.reconcileWebViewReturn();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _submit(PostEditComposerController controller) async {
    final current = ref
        .read(postEditComposerControllerProvider(widget.args))
        .value;
    if (current == null || !current.canSubmit) {
      return;
    }
    final danglingAids = controller.danglingAttachmentAids(current);
    if (danglingAids.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text(l10n.postEditDanglingAttachmentTitle),
            content: Text(l10n.postEditDanglingAttachmentBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.postEditDanglingAttachmentConfirm),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) {
        return;
      }
    }
    final result = await controller.submit();
    if (!mounted || !result.sent) {
      return;
    }
    _allowRoutePop = true;
    Navigator.of(context).pop(
      PostEditRouteResult(
        target: widget.args.target,
        outcome: PostEditRouteOutcome.saved,
        serverMutationPossible: true,
      ),
    );
  }

  void _syncMessageController(PostEditComposerState state) {
    if (_didApplyMessage &&
        (_lastAppliedMessage == state.message ||
            _messageController.text == state.message)) {
      _lastAppliedMessage = state.message;
      return;
    }
    _didApplyMessage = true;
    _messageController.value = TextEditingValue(
      text: state.message,
      selection: TextSelection.collapsed(offset: state.message.length),
    );
    _lastAppliedMessage = state.message;
  }

  void _syncSubjectController(PostEditComposerState state) {
    if (_didApplySubject &&
        (_lastAppliedSubject == state.subject ||
            _subjectController.text == state.subject)) {
      _lastAppliedSubject = state.subject;
      return;
    }
    _didApplySubject = true;
    _subjectController.value = TextEditingValue(
      text: state.subject,
      selection: TextSelection.collapsed(offset: state.subject.length),
    );
    _lastAppliedSubject = state.subject;
  }

  Future<void> _openWebView(PostEditComposerController controller) async {
    final routeFactory = ref.read(forumWebViewRouteFactoryProvider);
    final result = await Navigator.of(context).push<Object?>(
      routeFactory(
        ForumWebViewLaunchConfig(
          initialUri: widget.args.target.editUri,
          popOnRootBack: true,
          purpose: ForumWebViewHostPurpose.postEditFallback,
          completionTarget: ForumWebViewCompletionTarget(
            tid: widget.args.target.tid,
            pid: widget.args.target.pid,
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await controller.reconcileWebViewReturn();
    if (!mounted) {
      return;
    }
    final state = ref
        .read(postEditComposerControllerProvider(widget.args))
        .value;
    if (state?.webReturnVerificationState ==
        PostEditWebReturnVerificationState.changedClean) {
      _allowRoutePop = true;
      Navigator.of(context).pop(
        PostEditRouteResult(
          target: widget.args.target,
          outcome: PostEditRouteOutcome.serverChanged,
          serverMutationPossible: true,
        ),
      );
    }
    // The route result is intentionally only a hint. The authoritative state
    // is the fresh edit-form read performed by the controller above.
    assert(result == null || result is ForumWebViewRouteResult);
  }

  void _popDismissed(PostEditComposerState? state) {
    if (!mounted) {
      return;
    }
    _allowRoutePop = true;
    Navigator.of(context).pop(
      PostEditRouteResult(
        target: widget.args.target,
        outcome: PostEditRouteOutcome.dismissed,
        serverMutationPossible: state?.mayHaveServerMutationOnExit ?? false,
      ),
    );
  }
}

class _PostEditComposerBody extends StatelessWidget {
  const _PostEditComposerBody({
    required this.state,
    required this.subjectController,
    required this.messageController,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    required this.onSubjectChanged,
    required this.attachmentResolver,
    required this.attachmentPanelBuilder,
    required this.onImagePressed,
    required this.onUseServerVersion,
    required this.onKeepLocalVersion,
    required this.onRetryVerification,
  });

  final PostEditComposerState state;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<String> onSubjectChanged;
  final ComposerAttachmentPreviewResolver attachmentResolver;
  final WidgetBuilder attachmentPanelBuilder;
  final ComposerImageInsertCallback onImagePressed;
  final Future<void> Function() onUseServerVersion;
  final Future<void> Function() onKeepLocalVersion;
  final Future<void> Function() onRetryVerification;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final deletedReferences = const ComposerAttachBbCodeService()
        .extractAttachAids(state.message)
        .where(
          (aid) => state.attachmentSession.deletedAidTombstones.contains(aid),
        )
        .isNotEmpty;
    final editor = ComposerMessageEditorSurface(
      surface: ComposerSurfacePreference.quill,
      message: state.message,
      sourceController: messageController,
      enabled: !state.isSubmitting,
      bbCodeRenderer: bbCodeRenderer,
      stickerGroups: stickerGroups,
      stickers: [for (final group in stickerGroups) ...group.stickers],
      initialStickerGroupId: initialStickerGroupId,
      onStickerGroupChanged: onStickerGroupChanged,
      onMessageChanged: onMessageChanged,
      imageAttachments: state.imageAttachments,
      keyPrefix: 'post-edit-composer',
      hintText: l10n.postEditMessageHint,
      messageRevision: state.messageRevision,
      lastMessageMutation: state.lastMessageMutation,
      isUploadingImages: state.isUploadingImages,
      imageUploadCurrent: state.imageUploadCurrent,
      imageUploadTotal: state.imageUploadTotal,
      attachmentResolver: attachmentResolver,
      onImagePressed: onImagePressed,
      extraToolbarActions: [
        ComposerToolbarAction.panel(
          key: const Key('post-edit-manage-images-button'),
          icon: Icons.photo_library_outlined,
          tooltip: l10n.postEditManageImages,
          panelBuilder: attachmentPanelBuilder,
        ),
      ],
    );
    return SafeArea(
      key: const Key('post-edit-composer-safe-area'),
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.pendingConflict != null)
            _PostEditConflictBanner(
              onUseServerVersion: onUseServerVersion,
              onKeepLocalVersion: onKeepLocalVersion,
            ),
          if (state.webReturnVerificationState ==
              PostEditWebReturnVerificationState.unconfirmed)
            ComposerStatusBanner.error(
              key: const Key('post-edit-unconfirmed-banner'),
              text: l10n.postEditVerificationFailed,
              retryButtonKey: const Key('post-edit-retry-verification'),
              retryLabel: l10n.postEditRetryVerification,
              onRetry: onRetryVerification,
            ),
          if (state.submitState == PostEditSubmitState.submitting)
            ComposerStatusBanner.info(
              key: const Key('post-edit-submit-progress-banner'),
              text: l10n.postEditSubmitInProgress,
            ),
          if (state.submitState == PostEditSubmitState.partialSuccess)
            ComposerStatusBanner.info(
              key: const Key('post-edit-partial-success-banner'),
              text: l10n.postEditPartialSuccess,
            ),
          if (state.submitState == PostEditSubmitState.unconfirmed)
            ComposerStatusBanner.error(
              key: const Key('post-edit-submit-unconfirmed-banner'),
              text: l10n.postEditSubmitUnconfirmed,
              retryButtonKey: const Key('post-edit-submit-retry-button'),
              retryLabel: l10n.postEditRetryVerification,
              onRetry: onRetryVerification,
            ),
          if (state.lastSubmitOutcome ==
              PostEditSubmitResponseKind.authenticationFailure)
            ComposerStatusBanner.error(
              key: const Key('post-edit-authentication-failure-banner'),
              text: l10n.postEditAuthenticationRequired,
              retryButtonKey: const Key(
                'post-edit-authentication-retry-button',
              ),
              retryLabel: l10n.postEditRetryVerification,
              onRetry: onRetryVerification,
            ),
          if (state.lastSubmitOutcome ==
              PostEditSubmitResponseKind.permissionFailure)
            ComposerStatusBanner.info(
              key: const Key('post-edit-permission-failure-banner'),
              text: l10n.postEditPermissionDenied,
            ),
          if (state.lastSubmitOutcome ==
              PostEditSubmitResponseKind.businessFailure)
            ComposerStatusBanner.info(
              key: const Key('post-edit-submit-failure-banner'),
              text: l10n.postEditSubmitFailed,
            ),
          if (state.lastAttachmentDeleteOutcome ==
              PostEditAttachmentDeleteOutcome.notDeleted)
            ComposerStatusBanner.info(
              key: const Key('post-edit-delete-image-failed-banner'),
              text: l10n.postEditDeleteImageFailed,
            ),
          if (state.attachmentVerificationUnconfirmed)
            ComposerStatusBanner.info(
              key: const Key('post-edit-delete-image-unconfirmed-banner'),
              text: l10n.postEditDeleteImageUnconfirmed,
            ),
          if (deletedReferences)
            ComposerStatusBanner.info(
              key: const Key('post-edit-deleted-image-reference-banner'),
              text: l10n.postEditDeletedImageReferenceWarning,
            ),
          if (state.target.isFirstPost) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ForumContentSpacing.composerPageHorizontal,
                ForumContentSpacing.composerPageVertical,
                ForumContentSpacing.composerPageHorizontal,
                0,
              ),
              child: ThreadSubjectField(
                fieldKey: const Key('post-edit-subject-input'),
                controller: subjectController,
                enabled: !state.isSubmitting,
                onChanged: onSubjectChanged,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(child: editor),
        ],
      ),
    );
  }
}

class _PostEditConflictBanner extends StatelessWidget {
  const _PostEditConflictBanner({
    required this.onUseServerVersion,
    required this.onKeepLocalVersion,
  });

  final Future<void> Function() onUseServerVersion;
  final Future<void> Function() onKeepLocalVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('post-edit-conflict-banner'),
      padding: const EdgeInsets.all(12),
      color: colors.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.postEditConflictTitle,
            style: TextStyle(color: colors.onErrorContainer),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.postEditConflictBody,
            style: TextStyle(color: colors.onErrorContainer),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('post-edit-use-server-button'),
                onPressed: () => unawaited(onUseServerVersion()),
                child: Text(l10n.postEditUseServer),
              ),
              FilledButton(
                key: const Key('post-edit-keep-local-button'),
                onPressed: () => unawaited(onKeepLocalVersion()),
                child: Text(l10n.postEditKeepLocal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
