import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_toolbar.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_editor_preview.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_image_attachment_queue.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/features/composer_shared/presentation/widgets/sticker_picker_sheet.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/posting_composer_controller.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/posting/presentation/widgets/thread_poll_editor.dart';
import 'package:y300/features/posting/presentation/widgets/thread_special_switch.dart';
import 'package:y300/features/posting/presentation/widgets/thread_subject_field.dart';
import 'package:y300/features/posting/presentation/widgets/thread_tags_field.dart';
import 'package:y300/features/posting/presentation/widgets/thread_type_selector.dart';

/// 自制发帖页。
///
/// 沿用 reply 页的整体节奏（StatefulWidget + AsyncNotifier 单向数据流 +
/// 标题/正文 TextEditingController 自维护 + PopScope 保存草稿），但比 reply
/// 多了：标题输入框、主题分类选择器、更多设置抽屉，以及 metadata 加载
/// SnackBar 提示。AppBar 标题随 metadata 加载完成后变为"发帖 — {forumName}"。
class PostingComposerPage extends ConsumerStatefulWidget {
  const PostingComposerPage({super.key, required this.args});

  final PostingComposerArgs args;

  @override
  ConsumerState<PostingComposerPage> createState() =>
      _PostingComposerPageState();
}

class _PostingComposerPageState extends ConsumerState<PostingComposerPage> {
  static const _bbCodeInsertionService = ComposerBbCodeInsertionService();

  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  PostingComposerController? _controller;
  bool _didApplyRestoredDraft = false;
  bool _didNotifyRestoredDraft = false;
  bool _wasLoadingMetadata = false;
  bool _allowPopWithoutConfirm = false;
  String? _lastAppliedStateMessage;
  String? _lastAppliedStateSubject;
  Set<String> _notifiedUploadedAttachmentIds = const <String>{};

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
    final stickerGroups = ref
        .watch(stickerGroupsProvider)
        .maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    _controller = controller;
    final state = asyncState.value;
    if (state != null) {
      _syncTextControllers(state);
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
          title: Text(_appBarTitle(state)),
          actions: [
            IconButton(
              key: const Key('posting-composer-more-button'),
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
              key: const Key('posting-composer-image-button'),
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
              key: const Key('posting-composer-send-button'),
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
            onSelectedTypeIdChanged: controller.updateSelectedTypeId,
            onRetryLoadMetadata: controller.retryLoadMetadata,
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
            onBbCodeCommandSelected: (command) {
              _insertBbCode(command, controller);
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
    return [for (final group in groups) ...group.stickers];
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

  void _scheduleTransientFeedback(PostingComposerState state) {
    final shouldNotifyMetadataLoading =
        state.isLoadingMetadata && !_wasLoadingMetadata;
    _wasLoadingMetadata = state.isLoadingMetadata;
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
    if (!shouldNotifyMetadataLoading &&
        !shouldNotifyRestoredDraft &&
        newUploadedIds.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (shouldNotifyRestoredDraft) {
        final message = state.tags.isNotEmpty
            ? '已恢复未发送的草稿，请注意已恢复的主题标签'
            : '已恢复未发送草稿';
        showComposerSnackBar(context, message);
        return;
      }
      if (shouldNotifyMetadataLoading) {
        showComposerSnackBar(context, '正在加载发帖表单');
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

  void _insertBbCode(
    ComposerBbCodeCommand command,
    PostingComposerController controller,
  ) {
    final nextValue = _bbCodeInsertionService.wrapSelection(
      _messageController.value,
      command,
    );
    _messageController.value = nextValue;
    controller.updateMessage(nextValue.text);
    _lastAppliedStateMessage = nextValue.text;
  }

  void _showSettingsSheet() {
    final provider = postingComposerControllerProvider(widget.args);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Consumer(
          builder: (context, ref, _) {
            final sheetState = ref.watch(provider).value;
            final enabled = sheetState != null && !sheetState.isSubmitting;
            final notifier = ref.read(provider.notifier);
            return ComposerSettingsSheet(
              key: const Key('posting-composer-settings-sheet'),
              title: '更多设置',
              children: [
                ThreadTagsField(
                  containerKey: const Key('posting-composer-tags-field'),
                  inputFieldKey: const Key('posting-composer-tags-input'),
                  chipKeyBuilder: (tag, index) =>
                      Key('posting-composer-tag-chip-$index'),
                  tags: sheetState?.tags ?? const <String>[],
                  onChanged: notifier.updateTags,
                  enabled: enabled,
                ),
                const SizedBox(height: 12),
                ComposerSettingsSwitchTile(
                  tileKey: const Key('posting-composer-use-signature-switch'),
                  title: '使用个人签名',
                  value: sheetState?.useSignature ?? false,
                  onChanged: notifier.toggleUseSignature,
                  enabled: enabled,
                ),
                ComposerSettingsSwitchTile(
                  tileKey: const Key(
                    'posting-composer-allow-notice-author-switch',
                  ),
                  title: '允许通知作者',
                  value: sheetState?.allowNoticeAuthor ?? false,
                  onChanged: notifier.updateAllowNoticeAuthor,
                  enabled: enabled,
                ),
                ComposerSettingsSwitchTile(
                  tileKey: const Key('posting-composer-bbcode-off-switch'),
                  title: '关闭 BBCode 解析',
                  value: sheetState?.bbCodeOff ?? false,
                  onChanged: notifier.updateBbCodeOff,
                  enabled: enabled,
                ),
                ComposerSettingsSwitchTile(
                  tileKey: const Key('posting-composer-smiley-off-switch'),
                  title: '关闭表情解析',
                  value: sheetState?.smileyOff ?? false,
                  onChanged: notifier.updateSmileyOff,
                  enabled: enabled,
                ),
                ComposerSettingsSwitchTile(
                  tileKey: const Key('posting-composer-parseurl-off-switch'),
                  title: '关闭 URL 解析',
                  value: sheetState?.parseUrlOff ?? false,
                  onChanged: notifier.updateParseUrlOff,
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

class _PostingComposerBody extends StatelessWidget {
  const _PostingComposerBody({
    required this.state,
    required this.bbCodeRenderer,
    required this.stickers,
    required this.subjectController,
    required this.messageController,
    required this.onSubjectChanged,
    required this.onMessageChanged,
    required this.onSelectedTypeIdChanged,
    required this.onRetryLoadMetadata,
    required this.onSpecialChanged,
    required this.onPollOptionsChanged,
    required this.onPollMultipleChanged,
    required this.onPollMaxChoicesChanged,
    required this.onPollExpirationDaysChanged,
    required this.onPollOvertChanged,
    required this.onPollVisibilityPollChanged,
    required this.onStickerPressed,
    required this.onBbCodeCommandSelected,
  });

  final PostingComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerItem> stickers;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<String?> onSelectedTypeIdChanged;
  final VoidCallback onRetryLoadMetadata;
  final ValueChanged<NewThreadSpecial> onSpecialChanged;
  final ValueChanged<List<String>> onPollOptionsChanged;
  final ValueChanged<bool> onPollMultipleChanged;
  final ValueChanged<int> onPollMaxChoicesChanged;
  final ValueChanged<int> onPollExpirationDaysChanged;
  final ValueChanged<bool> onPollOvertChanged;
  final ValueChanged<bool> onPollVisibilityPollChanged;
  final VoidCallback onStickerPressed;
  final ValueChanged<ComposerBbCodeCommand> onBbCodeCommandSelected;

  // PLACEHOLDER_PHASE_5_BODY_BUILD
  @override
  Widget build(BuildContext context) {
    final disabled = state.isSubmitting;
    final visibleAttachments = visibleComposerImageAttachments(
      state.imageAttachments,
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMetadataBanner(),
          _buildMetadataSpacer(),
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
          if (state.metadata != null &&
              state.metadata!.threadTypes.isNotEmpty &&
              state.metadata!.typeRequired) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ThreadTypeSelector(
                    containerKey: const Key('posting-composer-type-selector'),
                    toggleKey: const Key('posting-composer-type-toggle'),
                    summaryKey: const Key('posting-composer-type-summary'),
                    noneChipKey: const Key('posting-composer-type-none'),
                    chipKeyBuilder: (type) =>
                        Key('posting-composer-type-${type.id}'),
                    types: state.metadata!.threadTypes,
                    typeRequired: state.metadata!.typeRequired,
                    selectedTypeId: state.selectedTypeId,
                    onSelected: onSelectedTypeIdChanged,
                    enabled: !disabled,
                    useDropdown: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ThreadSpecialSwitch(
                    widgetKey: const Key('posting-composer-special-switch'),
                    summaryKey: const Key('posting-composer-special-summary'),
                    normalItemKey: const Key('posting-composer-special-normal'),
                    pollItemKey: const Key('posting-composer-special-poll'),
                    special: state.special,
                    onChanged: onSpecialChanged,
                    enabled: !disabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ] else if (state.metadata != null &&
              state.metadata!.threadTypes.isNotEmpty) ...[
            ThreadTypeSelector(
              containerKey: const Key('posting-composer-type-selector'),
              toggleKey: const Key('posting-composer-type-toggle'),
              summaryKey: const Key('posting-composer-type-summary'),
              noneChipKey: const Key('posting-composer-type-none'),
              chipKeyBuilder: (type) => Key('posting-composer-type-${type.id}'),
              types: state.metadata!.threadTypes,
              typeRequired: state.metadata!.typeRequired,
              selectedTypeId: state.selectedTypeId,
              onSelected: onSelectedTypeIdChanged,
              enabled: !disabled,
            ),
            const SizedBox(height: 12),
            ThreadSpecialSwitch(
              widgetKey: const Key('posting-composer-special-switch'),
              summaryKey: const Key('posting-composer-special-summary'),
              normalItemKey: const Key('posting-composer-special-normal'),
              pollItemKey: const Key('posting-composer-special-poll'),
              special: state.special,
              onChanged: onSpecialChanged,
              enabled: !disabled,
            ),
            const SizedBox(height: 12),
          ] else ...[
            ThreadSpecialSwitch(
              widgetKey: const Key('posting-composer-special-switch'),
              summaryKey: const Key('posting-composer-special-summary'),
              normalItemKey: const Key('posting-composer-special-normal'),
              pollItemKey: const Key('posting-composer-special-poll'),
              special: state.special,
              onChanged: onSpecialChanged,
              enabled: !disabled,
            ),
            const SizedBox(height: 12),
          ],
          if (state.special == NewThreadSpecial.poll) ...[
            ThreadPollEditor(
              containerKey: const Key('posting-composer-poll-editor'),
              optionFieldKeyBuilder: (index) =>
                  Key('posting-composer-poll-option-$index'),
              optionRemoveKeyBuilder: (index) =>
                  Key('posting-composer-poll-option-remove-$index'),
              addOptionButtonKey: const Key('posting-composer-poll-add-option'),
              multipleSwitchKey: const Key(
                'posting-composer-poll-multiple-switch',
              ),
              maxChoicesFieldKey: const Key(
                'posting-composer-poll-max-choices',
              ),
              expirationFieldKey: const Key('posting-composer-poll-expiration'),
              overtSwitchKey: const Key('posting-composer-poll-overt-switch'),
              visibilityPollSwitchKey: const Key(
                'posting-composer-poll-visibility-switch',
              ),
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
          ComposerBbCodeToolbar(
            keyPrefix: 'posting-composer',
            enabled: !disabled,
            onStickerPressed: onStickerPressed,
            onCommandSelected: onBbCodeCommandSelected,
          ),
          const SizedBox(height: 12),
          ComposerEditorPreview(
            inputKey: const Key('posting-composer-message-input'),
            previewPanelKey: const Key('posting-composer-bbcode-preview-panel'),
            previewEmptyKey: const Key('posting-composer-bbcode-preview-empty'),
            previewLabelKey: const Key('posting-composer-preview-label'),
            controller: messageController,
            enabled: !disabled,
            hintText: '请注意图片仅在本地保存24小时',
            onChanged: onMessageChanged,
            renderer: bbCodeRenderer,
            stickers: stickers,
            imageAttachments: state.imageAttachments,
          ),
          // 正文字数计数（仅当 metadata 声明了上限）。
          if (state.metadata?.hasMessageLimit ?? false)
            _MessageCounter(
              counterKey: const Key('posting-composer-message-counter'),
              currentLength: state.message.length,
              maxLength: state.metadata!.maxMessageLength,
            ),
          if (visibleAttachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ComposerImageAttachmentQueue(
              containerKey: const Key('posting-composer-image-queue'),
              uploadCountKey: const Key('posting-composer-image-upload-count'),
              uploadProgressKey: const Key(
                'posting-composer-image-upload-progress',
              ),
              tileKeyBuilder: (attachment) => Key(
                'posting-composer-image-attachment-${attachment.localId}',
              ),
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
              key: const Key('posting-composer-error-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  /// metadata 加载中用 SnackBar 轻提示；只有失败态保留正文重试入口。
  Widget _buildMetadataBanner() {
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
    if (state.metadataError != null && state.metadataError!.trim().isNotEmpty) {
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
