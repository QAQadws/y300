import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_image_attachment_queue.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

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
  Set<String> _notifiedUploadedAttachmentIds = const <String>{};

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
          title: Text(widget.args.target.isPostReply ? '回复楼层' : '回复帖子'),
          actions: [
            IconButton(
              key: const Key('reply-composer-source-button'),
              tooltip: _editorSurface == ComposerSurfacePreference.quill
                  ? '源码'
                  : '返回编辑',
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
              tooltip: '更多',
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
              tooltip: '发送',
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
            message: '加载草稿失败：$error',
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
            onImagePressed: controller.pickImages,
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
    if (_didApplyRestoredDraft) {
      if (_lastAppliedStateMessage == state.message ||
          _messageController.text == state.message) {
        _lastAppliedStateMessage = state.message;
        return;
      }
      final nextOffset = state.message.length;
      _messageController.value = TextEditingValue(
        text: state.message,
        selection: TextSelection.collapsed(offset: nextOffset),
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

  void _scheduleTransientFeedback(ReplyComposerState state) {
    final shouldNotifyRestoredDraft =
        state.restoredDraft && !_didNotifyRestoredDraft;
    if (shouldNotifyRestoredDraft) {
      _didNotifyRestoredDraft = true;
    }
    final uploadedIds = uploadedComposerImageAttachmentIds(
      state.imageAttachments,
    );
    final newUploadedIds = uploadedIds.difference(
      _notifiedUploadedAttachmentIds,
    );
    _notifiedUploadedAttachmentIds = uploadedIds;
    if (!shouldNotifyRestoredDraft && newUploadedIds.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (shouldNotifyRestoredDraft) {
        showComposerSnackBar(context, '已恢复未发送草稿');
        return;
      }
      for (final attachment in state.imageAttachments) {
        if (newUploadedIds.contains(attachment.localId)) {
          showComposerSnackBar(context, '${attachment.fileName} 已上传');
          return;
        }
      }
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
        return AlertDialog(
          title: const Text('保存草稿并离开？'),
          content: const Text('当前回复还没有发送，离开前会保存为草稿。'),
          actions: [
            TextButton(
              key: const Key('reply-composer-continue-edit-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('继续编辑'),
            ),
            FilledButton(
              key: const Key('reply-composer-save-leave-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('保存草稿并离开'),
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
      showDragHandle: true,
      builder: (_) {
        return Consumer(
          builder: (context, ref, _) {
            final sheetState = ref.watch(provider).value;
            final enabled =
                sheetState != null &&
                !sheetState.isSubmitting &&
                !sheetState.isPreparing;
            return ComposerSettingsSheet(
              key: const Key('reply-composer-settings-sheet'),
              title: '更多设置',
              children: [
                ComposerSettingsSwitchTile(
                  tileKey: const Key('reply-composer-use-signature-switch'),
                  title: '使用个人签名',
                  value: sheetState?.useSignature ?? false,
                  onChanged: ref.read(provider.notifier).toggleUseSignature,
                  enabled: enabled,
                ),
              ],
            );
          },
        );
      },
    );
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
  final Future<void> Function() onImagePressed;

  @override
  Widget build(BuildContext context) {
    final visibleAttachments = visibleComposerImageAttachments(
      state.imageAttachments,
    );
    final editor = _ReplyMessageEditor(
      surface: editorSurface,
      state: state,
      bbCodeRenderer: bbCodeRenderer,
      stickerGroups: stickerGroups,
      messageController: messageController,
      initialStickerGroupId: initialStickerGroupId,
      onStickerGroupChanged: onStickerGroupChanged,
      onMessageChanged: onMessageChanged,
      onImagePressed: onImagePressed,
    );
    final topFeedback = _buildFeedbackWidgets(context, visibleAttachments);
    if (editorSurface == ComposerSurfacePreference.quill) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topFeedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
        padding: const EdgeInsets.all(16),
        children: [
          ..._buildLeadingFeedbackWidgets(context),
          editor,
          ..._buildTrailingFeedbackWidgets(context, visibleAttachments),
        ],
      ),
    );
  }

  List<Widget> _buildFeedbackWidgets(
    BuildContext context,
    List<ComposerImageAttachment> visibleAttachments,
  ) {
    return [
      ..._buildLeadingFeedbackWidgets(context),
      ..._buildTrailingFeedbackWidgets(context, visibleAttachments),
    ];
  }

  List<Widget> _buildLeadingFeedbackWidgets(BuildContext context) {
    return [
      if (state.target.isPostReply) ...[
        _ReplyReferenceStatus(state: state, onRetryPrepare: onRetryPrepare),
        const SizedBox(height: 12),
      ],
      if (state.imageUploadError != null &&
          state.imageUploadError!.trim().isNotEmpty) ...[
        Text(
          state.imageUploadError!,
          key: const Key('reply-composer-image-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildTrailingFeedbackWidgets(
    BuildContext context,
    List<ComposerImageAttachment> visibleAttachments,
  ) {
    return [
      if (visibleAttachments.isNotEmpty) ...[
        const SizedBox(height: 12),
        ComposerImageAttachmentQueue(
          containerKey: const Key('reply-composer-image-queue'),
          uploadCountKey: const Key('reply-composer-image-upload-count'),
          uploadProgressKey: const Key('reply-composer-image-upload-progress'),
          tileKeyBuilder: (attachment) =>
              Key('reply-composer-image-attachment-${attachment.localId}'),
          attachments: visibleAttachments,
          isUploadingImages: state.isUploadingImages,
          imageUploadCurrent: state.imageUploadCurrent,
          imageUploadTotal: state.imageUploadTotal,
        ),
      ],
      if (state.errorMessage != null &&
          state.errorMessage!.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          state.errorMessage!,
          key: const Key('reply-composer-error-message'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }
}

class _ReplyMessageEditor extends StatelessWidget {
  const _ReplyMessageEditor({
    required this.surface,
    required this.state,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.messageController,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    required this.onImagePressed,
  });

  final ComposerSurfacePreference surface;
  final ReplyComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final TextEditingController messageController;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final Future<void> Function() onImagePressed;

  @override
  Widget build(BuildContext context) {
    final enabled = !state.isSubmitting && !state.isPreparing;
    final stickers = [for (final group in stickerGroups) ...group.stickers];
    final renderer = bbCodeRenderer;
    return switch (surface) {
      ComposerSurfacePreference.quill => ComposerQuillEditorSurface(
        key: const Key('reply-composer-quill-editor'),
        keyPrefix: 'reply-composer',
        bbCode: state.message,
        enabled: enabled,
        stickers: stickers,
        stickerGroups: stickerGroups,
        initialStickerGroupId: initialStickerGroupId,
        onStickerGroupChanged: onStickerGroupChanged,
        imageAttachments: state.imageAttachments,
        attachImageBuilder: renderer is FlutterBbCodeForumRenderer
            ? renderer.attachImageBuilder
            : null,
        attachFileExists: renderer is FlutterBbCodeForumRenderer
            ? renderer.attachFileExists
            : null,
        hintText: '输入回复内容',
        expand: true,
        onBbCodeChanged: onMessageChanged,
        onImagePressed: (_) async {
          await onImagePressed();
          return null;
        },
      ),
      ComposerSurfacePreference.source => ComposerBbCodeSourceEditor(
        keyPrefix: 'reply-composer',
        viewKey: const Key('reply-composer-source-view'),
        inputKey: const Key('reply-composer-message-input'),
        controller: messageController,
        enabled: enabled,
        hintText: '输入回复内容',
        onChanged: onMessageChanged,
      ),
    };
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
      return const ComposerStatusBanner.loading(text: '正在准备楼层引用');
    }

    final error = state.preparationError;
    if (error != null && error.trim().isNotEmpty) {
      return ComposerStatusBanner.error(
        key: const Key('reply-composer-preparation-error'),
        text: error,
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
