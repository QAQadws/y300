import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_editor_preview.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_image_attachment_queue.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/reply/presentation/widgets/reply_editor_toolbar.dart';

class ReplyComposerPage extends ConsumerStatefulWidget {
  const ReplyComposerPage({super.key, required this.args});

  final ReplyComposerArgs args;

  @override
  ConsumerState<ReplyComposerPage> createState() => _ReplyComposerPageState();
}

class _ReplyComposerPageState extends ConsumerState<ReplyComposerPage> {
  late final TextEditingController _messageController;
  ReplyComposerController? _controller;
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
        appBar: AppBar(
          title: Text(widget.args.target.isPostReply ? '回复楼层' : '回复帖子'),
          actions: [
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
              key: const Key('reply-composer-image-button'),
              tooltip: '图片',
              onPressed: state == null || !state.canPickImages
                  ? null
                  : () {
                      unawaited(controller.pickImages());
                    },
              style: composerAppBarActionStyle(context),
              icon: const Icon(Icons.image),
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
            stickers: _flattenStickers(stickerGroups),
            messageController: _messageController,
            onMessageChanged: (value) {
              _lastAppliedStateMessage = value;
              controller.updateMessage(value);
            },
            onRetryPrepare: controller.retryPreparePostReply,
            onStickerPressed: () {
              unawaited(_pickAndInsertSticker(context, controller));
            },
          ),
        ),
      ),
    );
  }

  List<StickerItem> _flattenStickers(List<StickerGroup> groups) {
    return [for (final group in groups) ...group.stickers];
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

  Future<void> _pickAndInsertSticker(
    BuildContext context,
    ReplyComposerController controller,
  ) async {
    final sticker = await showModalBottomSheet<StickerItem>(
      context: context,
      showDragHandle: true,
      builder: (_) => const StickerPickerSheet(),
    );
    if (!mounted || sticker == null) {
      return;
    }
    _insertSticker(sticker, controller);
  }

  void _insertSticker(StickerItem sticker, ReplyComposerController controller) {
    final value = _messageController.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final normalizedStart = start.clamp(0, text.length).toInt();
    final normalizedEnd = end.clamp(0, text.length).toInt();
    final replaceStart = normalizedStart < normalizedEnd
        ? normalizedStart
        : normalizedEnd;
    final replaceEnd = normalizedStart < normalizedEnd
        ? normalizedEnd
        : normalizedStart;
    final nextText = text.replaceRange(replaceStart, replaceEnd, sticker.code);
    final nextOffset = replaceStart + sticker.code.length;
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    controller.updateMessage(nextText);
    _lastAppliedStateMessage = nextText;
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
    required this.stickers,
    required this.messageController,
    required this.onMessageChanged,
    required this.onRetryPrepare,
    required this.onStickerPressed,
  });

  final ReplyComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerItem> stickers;
  final TextEditingController messageController;
  final ValueChanged<String> onMessageChanged;
  final VoidCallback onRetryPrepare;
  final VoidCallback onStickerPressed;

  @override
  Widget build(BuildContext context) {
    final visibleAttachments = visibleComposerImageAttachments(
      state.imageAttachments,
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          ReplyEditorToolbar(
            enabled: !state.isSubmitting && !state.isPreparing,
            onStickerPressed: onStickerPressed,
          ),
          const SizedBox(height: 12),
          ComposerEditorPreview(
            inputKey: const Key('reply-composer-message-input'),
            previewLabelKey: const Key('reply-composer-preview-label'),
            controller: messageController,
            enabled: !state.isSubmitting && !state.isPreparing,
            hintText: '输入回复内容',
            onChanged: onMessageChanged,
            renderer: bbCodeRenderer,
            stickers: stickers,
            imageAttachments: state.imageAttachments,
          ),
          if (visibleAttachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ComposerImageAttachmentQueue(
              containerKey: const Key('reply-composer-image-queue'),
              uploadCountKey: const Key('reply-composer-image-upload-count'),
              uploadProgressKey: const Key(
                'reply-composer-image-upload-progress',
              ),
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
        ],
      ),
    );
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
