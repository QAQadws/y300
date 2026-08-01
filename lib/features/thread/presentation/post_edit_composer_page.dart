import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_message_editor_surface.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_controller.dart';
import 'package:y300/features/thread/presentation/post_edit_composer_state.dart';
import 'package:y300/l10n/app_localizations.dart';

class PostEditComposerPage extends ConsumerStatefulWidget {
  const PostEditComposerPage({super.key, required this.args});

  final PostEditComposerArgs args;

  @override
  ConsumerState<PostEditComposerPage> createState() =>
      _PostEditComposerPageState();
}

class _PostEditComposerPageState extends ConsumerState<PostEditComposerPage> {
  late final TextEditingController _messageController;
  ComposerSurfacePreference _editorSurface = ComposerSurfacePreference.quill;
  bool _didApplySurfacePreference = false;
  bool _didApplyMessage = false;
  bool _allowPopWithoutConfirm = false;
  String? _lastAppliedMessage;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    final provider = postEditComposerControllerProvider(widget.args);
    unawaited(ref.read(provider.notifier).flushDraft());
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
    final preferences = ref.watch(composerPreferencesControllerProvider);
    if (!_didApplySurfacePreference && preferences.hasValue) {
      _didApplySurfacePreference = true;
      _editorSurface = preferences.value!.defaultSurface;
    }
    if (state != null) {
      _syncMessageController(state);
    }

    return PopScope(
      canPop: _allowPopWithoutConfirm || !_shouldConfirmPop(state),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmAndPop(controller));
        }
      },
      child: Scaffold(
        key: const Key('post-edit-composer-page'),
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
              key: const Key('post-edit-more-button'),
              tooltip: l10n.composerMore,
              onPressed: state == null ? null : _showSettingsSheet,
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.more_vert),
            ),
            IconButton(
              key: const Key('post-edit-save-button'),
              tooltip: l10n.postEditSave,
              onPressed: null,
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ComposerLoadErrorView(
            message: l10n.composerLoadDraftFailed(error.toString()),
            textKey: const Key('post-edit-load-error'),
          ),
          data: (value) => _PostEditComposerBody(
            state: value,
            editorSurface: _editorSurface,
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
            onUseServerVersion: controller.useServerVersion,
            onKeepLocalVersion: controller.keepLocalVersion,
            onRetryVerification: controller.reconcileWebViewReturn,
          ),
        ),
      ),
    );
  }

  bool _shouldConfirmPop(PostEditComposerState? state) {
    return state?.isDirtyAgainstBaseline ?? false;
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

  void _toggleEditorSurface(PostEditComposerState state) {
    final previous = _editorSurface;
    final next = previous == ComposerSurfacePreference.quill
        ? ComposerSurfacePreference.source
        : ComposerSurfacePreference.quill;
    setState(() {
      if (previous == ComposerSurfacePreference.quill) {
        _messageController.text = state.message;
        _lastAppliedMessage = state.message;
      }
      _editorSurface = next;
    });
    unawaited(
      ref
          .read(composerPreferencesControllerProvider.notifier)
          .setDefaultSurface(next),
    );
  }

  Future<void> _openWebView(PostEditComposerController controller) async {
    final routeFactory = ref.read(forumWebViewRouteFactoryProvider);
    final result = await Navigator.of(context).push<Object?>(
      routeFactory(
        ForumWebViewLaunchConfig(
          initialUri: widget.args.snapshot.target.editUri,
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
      _allowPopWithoutConfirm = true;
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

  Future<void> _confirmAndPop(PostEditComposerController controller) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.postEditLeaveTitle),
          content: Text(l10n.postEditLeaveBody),
          actions: [
            TextButton(
              key: const Key('post-edit-continue-button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.composerContinueEditing),
            ),
            FilledButton(
              key: const Key('post-edit-save-draft-leave-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
    Navigator.of(context).pop(
      PostEditRouteResult(
        target: widget.args.target,
        outcome: PostEditRouteOutcome.dismissed,
      ),
    );
  }

  void _showSettingsSheet() {
    final provider = postEditComposerControllerProvider(widget.args);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final l10n = AppLocalizations.of(context);
            final state = ref.watch(provider).value;
            final canReset = state != null && state.isDirtyAgainstBaseline;
            final nextLabel = _editorSurface == ComposerSurfacePreference.quill
                ? l10n.composerSourceMode
                : l10n.composerVisualMode;
            return ComposerSettingsSheet(
              key: const Key('post-edit-settings-sheet'),
              title: l10n.composerMoreSettings,
              children: [
                ComposerSettingsActionTile(
                  tileKey: const Key('post-edit-surface-toggle'),
                  icon: _editorSurface == ComposerSurfacePreference.quill
                      ? Icons.code
                      : Icons.edit_outlined,
                  title: nextLabel,
                  onPressed: state == null
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _toggleEditorSurface(state);
                        },
                ),
                const Divider(),
                ComposerSettingsActionTile(
                  tileKey: const Key('post-edit-reset-baseline'),
                  icon: Icons.restart_alt,
                  title: l10n.postEditRestoreServer,
                  destructive: true,
                  onPressed: canReset
                      ? () {
                          Navigator.of(sheetContext).pop();
                          unawaited(ref.read(provider.notifier).resetDraft());
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
}

class _PostEditComposerBody extends StatelessWidget {
  const _PostEditComposerBody({
    required this.state,
    required this.editorSurface,
    required this.messageController,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    required this.onUseServerVersion,
    required this.onKeepLocalVersion,
    required this.onRetryVerification,
  });

  final PostEditComposerState state;
  final ComposerSurfacePreference editorSurface;
  final TextEditingController messageController;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final Future<void> Function() onUseServerVersion;
  final Future<void> Function() onKeepLocalVersion;
  final Future<void> Function() onRetryVerification;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editor = ComposerMessageEditorSurface(
      surface: editorSurface,
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
    );
    return SafeArea(
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
              onRetry: onRetryVerification,
            ),
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
