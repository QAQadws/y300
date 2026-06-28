import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';
import 'package:y300/features/composer_shared/presentation/widgets/bbcode_preview_panel.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_image_attachment_queue.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_mode_switch.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_restored_draft_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/posting_composer_controller.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/posting/presentation/widgets/posting_options_panel.dart';
import 'package:y300/features/posting/presentation/widgets/thread_poll_editor.dart';
import 'package:y300/features/posting/presentation/widgets/thread_special_switch.dart';
import 'package:y300/features/posting/presentation/widgets/thread_subject_field.dart';
import 'package:y300/features/posting/presentation/widgets/thread_tags_field.dart';
import 'package:y300/features/posting/presentation/widgets/thread_type_selector.dart';
import 'package:y300/features/reply/presentation/widgets/reply_editor_toolbar.dart';

/// 自制发帖页。
///
/// 沿用 reply 页的整体节奏（StatefulWidget + AsyncNotifier 单向数据流 +
/// 标题/正文 TextEditingController 自维护 + PopScope 保存草稿），但比 reply
/// 多了：标题输入框、主题分类选择器、五项发布选项面板，以及顶部"加载 metadata"
/// 状态条。AppBar 标题随 metadata 加载完成后变为"发帖 — {forumName}"。
class PostingComposerPage extends ConsumerStatefulWidget {
  const PostingComposerPage({
    super.key,
    required this.args,
  });

  final PostingComposerArgs args;

  @override
  ConsumerState<PostingComposerPage> createState() =>
      _PostingComposerPageState();
}

class _PostingComposerPageState extends ConsumerState<PostingComposerPage> {
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  PostingComposerController? _controller;
  bool _didApplyRestoredDraft = false;
  bool _allowPopWithoutConfirm = false;
  String? _lastAppliedStateMessage;
  String? _lastAppliedStateSubject;

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      // 即使页面被销毁，也要把当前内容落盘——这是 reply 现有约定，沿用它。
      unawaited(controller.flushDraft());
    }
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // PLACEHOLDER_PHASE_5_BUILD_AND_HELPERS
  @override
  Widget build(BuildContext context) {
    final provider = postingComposerControllerProvider(widget.args);
    final asyncState = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final bbCodeRenderer = ref.watch(forumBbCodeRendererProvider);
    final stickerGroups = ref.watch(stickerGroupsProvider).maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    _controller = controller;
    final state = asyncState.value;
    if (state != null) {
      _syncTextControllers(state);
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
          title: Text(_appBarTitle(state)),
          actions: [
            IconButton(
              key: const Key('posting-composer-image-button'),
              tooltip: '图片',
              onPressed: state == null || !state.canPickImages
                  ? null
                  : () {
                      unawaited(controller.pickImages());
                    },
              icon: const Icon(Icons.image),
            ),
            IconButton(
              key: const Key('posting-composer-send-button'),
              tooltip: '发送',
              onPressed: state == null || !state.canSubmit
                  ? null
                  : () {
                      unawaited(_submit(context, controller));
                    },
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ComposerLoadErrorView(
            message: '加载草稿失败：$error',
            textKey: const Key('posting-composer-load-error'),
          ),
          data: (state) => _PostingComposerBody(
            state: state,
            bbCodeRenderer: bbCodeRenderer,
            stickers: _flattenStickers(stickerGroups),
            subjectController: _subjectController,
            messageController: _messageController,
            onSubjectChanged: (value) {
              _lastAppliedStateSubject = value;
              controller.updateSubject(value);
            },
            onMessageChanged: (value) {
              _lastAppliedStateMessage = value;
              controller.updateMessage(value);
            },
            onModeChanged: controller.switchMode,
            onUseSignatureChanged: controller.toggleUseSignature,
            onAllowNoticeAuthorChanged: controller.updateAllowNoticeAuthor,
            onBbCodeOffChanged: controller.updateBbCodeOff,
            onSmileyOffChanged: controller.updateSmileyOff,
            onParseUrlOffChanged: controller.updateParseUrlOff,
            onSelectedTypeIdChanged: controller.updateSelectedTypeId,
            onRetryLoadMetadata: controller.retryLoadMetadata,
            onTagsChanged: controller.updateTags,
            onSpecialChanged: controller.updateSpecial,
            onPollOptionsChanged: controller.updatePollOptions,
            onPollMultipleChanged: controller.updatePollMultiple,
            onPollMaxChoicesChanged: controller.updatePollMaxChoices,
            onPollExpirationDaysChanged: controller.updatePollExpirationDays,
            onPollOvertChanged: controller.updatePollOvert,
            onPollVisibilityPollChanged: controller.updatePollVisibilityPoll,
            onStickerPressed: () {
              unawaited(_pickAndInsertSticker(context, controller));
            },
          ),
        ),
      ),
    );
  }

  String _appBarTitle(PostingComposerState? state) {
    final forumName = state?.metadata?.forumName.trim();
    if (forumName == null || forumName.isEmpty) {
      return '发帖';
    }
    return '发帖 — $forumName';
  }

  List<StickerItem> _flattenStickers(List<StickerGroup> groups) {
    return [
      for (final group in groups) ...group.stickers,
    ];
  }

  void _syncTextControllers(PostingComposerState state) {
    if (_didApplyRestoredDraft) {
      // 标题
      if (_lastAppliedStateSubject != state.subject &&
          _subjectController.text != state.subject) {
        _subjectController.value = TextEditingValue(
          text: state.subject,
          selection: TextSelection.collapsed(offset: state.subject.length),
        );
      }
      _lastAppliedStateSubject = state.subject;
      // 正文
      if (_lastAppliedStateMessage != state.message &&
          _messageController.text != state.message) {
        _messageController.value = TextEditingValue(
          text: state.message,
          selection: TextSelection.collapsed(offset: state.message.length),
        );
      }
      _lastAppliedStateMessage = state.message;
      return;
    }
    _didApplyRestoredDraft = true;
    _subjectController.value = TextEditingValue(
      text: state.subject,
      selection: TextSelection.collapsed(offset: state.subject.length),
    );
    _messageController.value = TextEditingValue(
      text: state.message,
      selection: TextSelection.collapsed(offset: state.message.length),
    );
    _lastAppliedStateSubject = state.subject;
    _lastAppliedStateMessage = state.message;
  }

  Future<void> _submit(
    BuildContext context,
    PostingComposerController controller,
  ) async {
    final navigator = Navigator.of(context);
    final result = await controller.submit();
    if (!mounted || !result.sent) {
      return;
    }
    _allowPopWithoutConfirm = true;
    navigator.pop(result);
  }

  bool _shouldConfirmPop(PostingComposerState? state) {
    if (_allowPopWithoutConfirm) {
      return false;
    }
    if (state == null) return false;
    if (state.subject.trim().isNotEmpty) return true;
    if (state.message.trim().isNotEmpty) return true;
    if (state.imageAttachments.isNotEmpty) return true;
    if (state.tags.isNotEmpty) return true;
    final pollOptions = state.poll?.options ?? const <String>[];
    if (pollOptions.any((option) => option.trim().isNotEmpty)) return true;
    return false;
  }

  Future<void> _confirmAndPop(
    BuildContext context,
    PostingComposerController controller,
  ) async {
    final navigator = Navigator.of(context);
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存草稿并离开？'),
          content: const Text('当前帖子还没有发送，离开前会保存为草稿。'),
          actions: [
            TextButton(
              key: const Key('posting-composer-continue-edit-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('继续编辑'),
            ),
            FilledButton(
              key: const Key('posting-composer-save-leave-button'),
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
    PostingComposerController controller,
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

  void _insertSticker(
    StickerItem sticker,
    PostingComposerController controller,
  ) {
    final value = _messageController.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final normalizedStart = start.clamp(0, text.length).toInt();
    final normalizedEnd = end.clamp(0, text.length).toInt();
    final replaceStart =
        normalizedStart < normalizedEnd ? normalizedStart : normalizedEnd;
    final replaceEnd =
        normalizedStart < normalizedEnd ? normalizedEnd : normalizedStart;
    final nextText = text.replaceRange(replaceStart, replaceEnd, sticker.code);
    final nextOffset = replaceStart + sticker.code.length;
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    controller.updateMessage(nextText);
    _lastAppliedStateMessage = nextText;
  }
}

class _PostingComposerBody extends StatelessWidget {
  const _PostingComposerBody({
    required this.state,
    required this.bbCodeRenderer,
    required this.stickers,
    required this.subjectController,
    required this.messageController,
    required this.onSubjectChanged,
    required this.onMessageChanged,
    required this.onModeChanged,
    required this.onUseSignatureChanged,
    required this.onAllowNoticeAuthorChanged,
    required this.onBbCodeOffChanged,
    required this.onSmileyOffChanged,
    required this.onParseUrlOffChanged,
    required this.onSelectedTypeIdChanged,
    required this.onRetryLoadMetadata,
    required this.onTagsChanged,
    required this.onSpecialChanged,
    required this.onPollOptionsChanged,
    required this.onPollMultipleChanged,
    required this.onPollMaxChoicesChanged,
    required this.onPollExpirationDaysChanged,
    required this.onPollOvertChanged,
    required this.onPollVisibilityPollChanged,
    required this.onStickerPressed,
  });

  final PostingComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerItem> stickers;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<ComposerEditorMode> onModeChanged;
  final ValueChanged<bool> onUseSignatureChanged;
  final ValueChanged<bool> onAllowNoticeAuthorChanged;
  final ValueChanged<bool> onBbCodeOffChanged;
  final ValueChanged<bool> onSmileyOffChanged;
  final ValueChanged<bool> onParseUrlOffChanged;
  final ValueChanged<String?> onSelectedTypeIdChanged;
  final VoidCallback onRetryLoadMetadata;
  final ValueChanged<List<String>> onTagsChanged;
  final ValueChanged<NewThreadSpecial> onSpecialChanged;
  final ValueChanged<List<String>> onPollOptionsChanged;
  final ValueChanged<bool> onPollMultipleChanged;
  final ValueChanged<int> onPollMaxChoicesChanged;
  final ValueChanged<int> onPollExpirationDaysChanged;
  final ValueChanged<bool> onPollOvertChanged;
  final ValueChanged<bool> onPollVisibilityPollChanged;
  final VoidCallback onStickerPressed;

  // PLACEHOLDER_PHASE_5_BODY_BUILD
  @override
  Widget build(BuildContext context) {
    final disabled = state.isSubmitting;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMetadataBanner(),
          _buildMetadataSpacer(),
          if (state.restoredDraft) ...[
            const ComposerRestoredDraftBanner(
              textKey: Key('posting-composer-restored-draft-banner'),
            ),
            const SizedBox(height: 12),
          ],
          if (state.imageUploadError != null &&
              state.imageUploadError!.trim().isNotEmpty) ...[
            Text(
              state.imageUploadError!,
              key: const Key('posting-composer-image-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          ThreadSubjectField(
            fieldKey: const Key('posting-composer-subject-input'),
            counterTextKey: const Key('posting-composer-subject-counter'),
            controller: subjectController,
            enabled: !disabled,
            onChanged: onSubjectChanged,
            maxLength: state.metadata?.maxSubjectLength ?? 0,
          ),
          const SizedBox(height: 12),
          ThreadTagsField(
            containerKey: const Key('posting-composer-tags-field'),
            inputFieldKey: const Key('posting-composer-tags-input'),
            chipKeyBuilder: (tag, index) =>
                Key('posting-composer-tag-chip-$index'),
            tags: state.tags,
            onChanged: onTagsChanged,
            enabled: !disabled,
          ),
          const SizedBox(height: 12),
          if (state.metadata != null && state.metadata!.threadTypes.isNotEmpty)
            ThreadTypeSelector(
              containerKey: const Key('posting-composer-type-selector'),
              noneChipKey: const Key('posting-composer-type-none'),
              chipKeyBuilder: (type) =>
                  Key('posting-composer-type-${type.id}'),
              types: state.metadata!.threadTypes,
              typeRequired: state.metadata!.typeRequired,
              selectedTypeId: state.selectedTypeId,
              onSelected: onSelectedTypeIdChanged,
              enabled: !disabled,
            ),
          if (state.metadata != null && state.metadata!.threadTypes.isNotEmpty)
            const SizedBox(height: 12),
          ThreadSpecialSwitch(
            widgetKey: const Key('posting-composer-special-switch'),
            special: state.special,
            onChanged: onSpecialChanged,
            enabled: !disabled,
          ),
          if (state.special == NewThreadSpecial.poll) ...[
            const SizedBox(height: 12),
            ThreadPollEditor(
              containerKey: const Key('posting-composer-poll-editor'),
              optionFieldKeyBuilder: (index) =>
                  Key('posting-composer-poll-option-$index'),
              optionRemoveKeyBuilder: (index) =>
                  Key('posting-composer-poll-option-remove-$index'),
              addOptionButtonKey:
                  const Key('posting-composer-poll-add-option'),
              multipleSwitchKey:
                  const Key('posting-composer-poll-multiple-switch'),
              maxChoicesFieldKey:
                  const Key('posting-composer-poll-max-choices'),
              expirationFieldKey:
                  const Key('posting-composer-poll-expiration'),
              overtSwitchKey: const Key('posting-composer-poll-overt-switch'),
              visibilityPollSwitchKey:
                  const Key('posting-composer-poll-visibility-switch'),
              poll: state.poll ?? NewThreadPollDraft.empty,
              enabled: !disabled,
              onOptionsChanged: onPollOptionsChanged,
              onMultipleChanged: onPollMultipleChanged,
              onMaxChoicesChanged: onPollMaxChoicesChanged,
              onExpirationDaysChanged: onPollExpirationDaysChanged,
              onOvertChanged: onPollOvertChanged,
              onVisibilityPollChanged: onPollVisibilityPollChanged,
            ),
          ],
          const SizedBox(height: 12),
          ComposerModeSwitch(
            widgetKey: const Key('posting-composer-mode-switch'),
            mode: state.mode,
            onModeChanged: onModeChanged,
            enabled: !disabled,
          ),
          const SizedBox(height: 12),
          ReplyEditorToolbar(
            // 暂沿用 reply 工具栏（只有"表情"按钮）；方案 §2.6 的
            // ComposerEditorToolbar slot 留待 Phase 7 体验润色阶段再扩展。
            enabled: !disabled,
            onStickerPressed: onStickerPressed,
          ),
          const SizedBox(height: 12),
          if (state.mode == ComposerEditorMode.source)
            TextField(
              key: const Key('posting-composer-message-input'),
              controller: messageController,
              enabled: !disabled,
              minLines: 8,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: onMessageChanged,
              decoration: const InputDecoration(
                hintText: '输入正文',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            )
          else
            BbCodePreviewPanel(
              source: state.message,
              renderer: bbCodeRenderer,
              stickers: stickers,
              imageAttachments: state.imageAttachments,
            ),
          // 正文字数计数（仅当 metadata 声明了上限）。源码 / 预览模式都展示，
          // 让用户在预览页也能看到提交前的字数对比。
          if (state.metadata?.hasMessageLimit ?? false)
            _MessageCounter(
              counterKey: const Key('posting-composer-message-counter'),
              currentLength: state.message.length,
              maxLength: state.metadata!.maxMessageLength,
            ),
          if (state.imageAttachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ComposerImageAttachmentQueue(
              containerKey: const Key('posting-composer-image-queue'),
              uploadCountKey: const Key('posting-composer-image-upload-count'),
              uploadProgressKey:
                  const Key('posting-composer-image-upload-progress'),
              tileKeyBuilder: (attachment) => Key(
                'posting-composer-image-attachment-${attachment.localId}',
              ),
              attachments: state.imageAttachments,
              isUploadingImages: state.isUploadingImages,
              imageUploadCurrent: state.imageUploadCurrent,
              imageUploadTotal: state.imageUploadTotal,
            ),
          ],
          const SizedBox(height: 12),
          PostingOptionsPanel(
            useSignatureKey: const Key('posting-composer-use-signature-switch'),
            allowNoticeAuthorKey:
                const Key('posting-composer-allow-notice-author-switch'),
            bbCodeOffKey: const Key('posting-composer-bbcode-off-switch'),
            smileyOffKey: const Key('posting-composer-smiley-off-switch'),
            parseUrlOffKey: const Key('posting-composer-parseurl-off-switch'),
            useSignature: state.useSignature,
            allowNoticeAuthor: state.allowNoticeAuthor,
            bbCodeOff: state.bbCodeOff,
            smileyOff: state.smileyOff,
            parseUrlOff: state.parseUrlOff,
            onUseSignatureChanged: onUseSignatureChanged,
            onAllowNoticeAuthorChanged: onAllowNoticeAuthorChanged,
            onBbCodeOffChanged: onBbCodeOffChanged,
            onSmileyOffChanged: onSmileyOffChanged,
            onParseUrlOffChanged: onParseUrlOffChanged,
            enabled: !disabled,
          ),
          if (state.errorMessage != null &&
              state.errorMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.errorMessage!,
              key: const Key('posting-composer-error-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  /// metadata 三种状态走同一个 [ComposerStatusBanner]：加载中 / 加载失败带重试 /
  /// 已加载（隐藏 banner）。
  Widget _buildMetadataBanner() {
    if (state.isLoadingMetadata) {
      return const ComposerStatusBanner.loading(
        key: Key('posting-composer-metadata-loading'),
        text: '正在加载发帖表单',
        textKey: Key('posting-composer-metadata-loading-text'),
      );
    }
    final error = state.metadataError;
    if (error != null && error.trim().isNotEmpty) {
      return ComposerStatusBanner.error(
        key: const Key('posting-composer-metadata-error'),
        text: '加载发帖表单失败：$error',
        textKey: const Key('posting-composer-metadata-error-text'),
        retryButtonKey: const Key('posting-composer-metadata-retry-button'),
        onRetry: onRetryLoadMetadata,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMetadataSpacer() {
    if (state.isLoadingMetadata ||
        (state.metadataError != null &&
            state.metadataError!.trim().isNotEmpty)) {
      return const SizedBox(height: 12);
    }
    return const SizedBox.shrink();
  }
}

/// 正文字数 / 上限提示行。仅在 metadata 声明了上限时由调用方渲染。
class _MessageCounter extends StatelessWidget {
  const _MessageCounter({
    required this.counterKey,
    required this.currentLength,
    required this.maxLength,
  });

  final Key counterKey;
  final int currentLength;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final exceeded = currentLength > maxLength;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$currentLength / $maxLength',
          key: counterKey,
          style: TextStyle(
            color: exceeded ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

