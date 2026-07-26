import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_app_bar_action_style.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_bbcode_source_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_load_error_view.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_settings_sheet.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/posting_composer_controller.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/posting/presentation/widgets/thread_poll_expandable_editor.dart';
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
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  PostingComposerController? _controller;
  ComposerSurfacePreference _editorSurface = ComposerSurfacePreference.quill;
  bool _didApplySurfacePreference = false;
  bool _didApplyRestoredDraft = false;
  bool _didNotifyRestoredDraft = false;
  bool _wasLoadingMetadata = false;
  bool _allowPopWithoutConfirm = false;
  String? _lastAppliedStateMessage;
  String? _lastAppliedStateSubject;
  final ComposerUploadFeedbackTracker _uploadFeedbackTracker =
      ComposerUploadFeedbackTracker();

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
        resizeToAvoidBottomInset:
            _editorSurface != ComposerSurfacePreference.quill,
        appBar: AppBar(
          title: Text(_appBarTitle(state)),
          actions: [
            IconButton(
              key: const Key('posting-composer-source-button'),
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
            stickerGroups: stickerGroups,
            stickers: _flattenStickers(stickerGroups),
            subjectController: _subjectController,
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

  void _toggleEditorSurface(PostingComposerState state) {
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
    final selection = _selectionForMessage(state);
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
          selection: selection,
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

  TextSelection _selectionForMessage(PostingComposerState state) {
    final mutation = state.lastMessageMutation;
    if (mutation != null && mutation.revision == state.messageRevision) {
      final offset = mutation.resultSelection.start
          .clamp(0, state.message.length)
          .toInt();
      return TextSelection.collapsed(offset: offset);
    }
    return TextSelection.collapsed(offset: state.message.length);
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
    final uploadMessages = _uploadFeedbackTracker.update(state);
    final messages = <String>[
      if (shouldNotifyRestoredDraft)
        state.tags.isNotEmpty ? '已恢复未发送的草稿，请注意已恢复的主题标签' : '已恢复未发送草稿',
      if (shouldNotifyMetadataLoading) '正在加载发帖表单',
      ...uploadMessages,
    ];
    if (messages.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showComposerSnackBar(context, messages.join('\n'));
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

  void _showSettingsSheet() {
    final provider = postingComposerControllerProvider(widget.args);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final sheetState = ref.watch(provider).value;
            final enabled = sheetState != null && !sheetState.isSubmitting;
            final notifier = ref.read(provider.notifier);
            final canReset =
                sheetState != null &&
                !sheetState.isSubmitting &&
                sheetState.hasDraftContent;
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
                const Divider(),
                ComposerSettingsActionTile(
                  tileKey: const Key('posting-composer-reset-draft-button'),
                  icon: Icons.restart_alt,
                  title: '重置草稿',
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

  Future<void> _confirmResetDraft(PostingComposerController controller) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('重置草稿？'),
          content: const Text('当前编辑内容和已选图片将被清空，且无法恢复。'),
          actions: [
            TextButton(
              key: const Key('posting-composer-reset-cancel-button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('posting-composer-reset-confirm-button'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('重置'),
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

class _PostingComposerBody extends StatefulWidget {
  const _PostingComposerBody({
    required this.state,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.stickers,
    required this.subjectController,
    required this.messageController,
    required this.editorSurface,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
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
    required this.onImagePressed,
  });

  final PostingComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final List<StickerItem> stickers;
  final TextEditingController subjectController;
  final TextEditingController messageController;
  final ComposerSurfacePreference editorSurface;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
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
  final ComposerImageInsertCallback onImagePressed;

  @override
  State<_PostingComposerBody> createState() => _PostingComposerBodyState();
}

class _PostingComposerBodyState extends State<_PostingComposerBody> {
  bool _isPollConfigExpanded = false;
  NewThreadSpecial? _lastSpecial;

  @override
  void initState() {
    super.initState();
    _lastSpecial = widget.state.special;
    _isPollConfigExpanded = widget.state.special == NewThreadSpecial.poll;
  }

  @override
  void didUpdateWidget(covariant _PostingComposerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPoll = _lastSpecial == NewThreadSpecial.poll;
    final isPoll = widget.state.special == NewThreadSpecial.poll;
    if (!wasPoll && isPoll) {
      _isPollConfigExpanded = true;
    } else if (wasPoll && !isPoll) {
      _isPollConfigExpanded = false;
    }
    _lastSpecial = widget.state.special;
  }

  @override
  Widget build(BuildContext context) {
    final editor = _PostingMessageEditor(
      surface: widget.editorSurface,
      state: widget.state,
      bbCodeRenderer: widget.bbCodeRenderer,
      stickerGroups: widget.stickerGroups,
      stickers: widget.stickers,
      messageController: widget.messageController,
      initialStickerGroupId: widget.initialStickerGroupId,
      onStickerGroupChanged: widget.onStickerGroupChanged,
      onMessageChanged: widget.onMessageChanged,
      onImagePressed: widget.onImagePressed,
    );
    if (widget.editorSurface == ComposerSurfacePreference.quill) {
      return SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._buildFormFields(context),
                    ..._buildTrailingFeedbackWidgets(context),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(hasScrollBody: false, child: editor),
          ],
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._buildFormFields(context),
          editor,
          if (widget.state.metadata?.hasMessageLimit ?? false)
            _MessageCounter(
              counterKey: const Key('posting-composer-message-counter'),
              currentLength: widget.state.message.length,
              maxLength: widget.state.metadata!.maxMessageLength,
            ),
          ..._buildTrailingFeedbackWidgets(context),
        ],
      ),
    );
  }

  List<Widget> _buildFormFields(BuildContext context) {
    final state = widget.state;
    final disabled = state.isSubmitting;
    return [
      if (state.pendingAttachmentMessage case final message?
          when message.trim().isNotEmpty) ...[
        ComposerStatusBanner.info(
          key: const Key('posting-composer-pending-attachment'),
          text: message,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
      ],
      _buildMetadataBanner(),
      _buildMetadataSpacer(),
      ThreadSubjectField(
        fieldKey: const Key('posting-composer-subject-input'),
        counterTextKey: const Key('posting-composer-subject-counter'),
        controller: widget.subjectController,
        enabled: !disabled,
        onChanged: widget.onSubjectChanged,
        maxLength: state.metadata?.maxSubjectLength ?? 0,
      ),
      const SizedBox(height: 12),
      ..._buildTypeAndSpecialFields(disabled: disabled),
      if (state.special == NewThreadSpecial.poll) ...[
        _buildPollEditor(disabled: disabled),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildTypeAndSpecialFields({required bool disabled}) {
    final state = widget.state;
    final metadata = state.metadata;
    if (metadata != null &&
        metadata.threadTypes.isNotEmpty &&
        metadata.typeRequired) {
      return [
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
                types: metadata.threadTypes,
                typeRequired: metadata.typeRequired,
                selectedTypeId: state.selectedTypeId,
                onSelected: widget.onSelectedTypeIdChanged,
                enabled: !disabled,
                useDropdown: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildSpecialSwitch(disabled: disabled)),
          ],
        ),
        const SizedBox(height: 12),
      ];
    }
    if (metadata != null && metadata.threadTypes.isNotEmpty) {
      return [
        ThreadTypeSelector(
          containerKey: const Key('posting-composer-type-selector'),
          toggleKey: const Key('posting-composer-type-toggle'),
          summaryKey: const Key('posting-composer-type-summary'),
          noneChipKey: const Key('posting-composer-type-none'),
          chipKeyBuilder: (type) => Key('posting-composer-type-${type.id}'),
          types: metadata.threadTypes,
          typeRequired: metadata.typeRequired,
          selectedTypeId: state.selectedTypeId,
          onSelected: widget.onSelectedTypeIdChanged,
          enabled: !disabled,
        ),
        const SizedBox(height: 12),
        _buildSpecialSwitch(disabled: disabled),
        const SizedBox(height: 12),
      ];
    }
    return [
      _buildSpecialSwitch(disabled: disabled),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildSpecialSwitch({required bool disabled}) {
    return ThreadSpecialSwitch(
      widgetKey: const Key('posting-composer-special-switch'),
      summaryKey: const Key('posting-composer-special-summary'),
      normalItemKey: const Key('posting-composer-special-normal'),
      pollItemKey: const Key('posting-composer-special-poll'),
      special: widget.state.special,
      onChanged: widget.onSpecialChanged,
      enabled: !disabled,
    );
  }

  Widget _buildPollEditor({required bool disabled}) {
    final state = widget.state;
    return ThreadPollExpandableEditor(
      toggleKey: const Key('posting-composer-poll-config-toggle'),
      summaryKey: const Key('posting-composer-poll-config-summary'),
      panelKey: const Key('posting-composer-poll-config-panel'),
      editorKey: const Key('posting-composer-poll-editor'),
      optionFieldKeyBuilder: (index) =>
          Key('posting-composer-poll-option-$index'),
      optionRemoveKeyBuilder: (index) =>
          Key('posting-composer-poll-option-remove-$index'),
      addOptionButtonKey: const Key('posting-composer-poll-add-option'),
      multipleSwitchKey: const Key('posting-composer-poll-multiple-switch'),
      maxChoicesFieldKey: const Key('posting-composer-poll-max-choices'),
      expirationFieldKey: const Key('posting-composer-poll-expiration'),
      overtSwitchKey: const Key('posting-composer-poll-overt-switch'),
      visibilityPollSwitchKey: const Key(
        'posting-composer-poll-visibility-switch',
      ),
      poll: state.poll ?? NewThreadPollDraft.empty,
      enabled: !disabled,
      expanded: _isPollConfigExpanded,
      onExpansionChanged: (expanded) {
        setState(() {
          _isPollConfigExpanded = expanded;
        });
      },
      onOptionsChanged: widget.onPollOptionsChanged,
      onMultipleChanged: widget.onPollMultipleChanged,
      onMaxChoicesChanged: widget.onPollMaxChoicesChanged,
      onExpirationDaysChanged: widget.onPollExpirationDaysChanged,
      onOvertChanged: widget.onPollOvertChanged,
      onVisibilityPollChanged: widget.onPollVisibilityPollChanged,
    );
  }

  List<Widget> _buildTrailingFeedbackWidgets(BuildContext context) {
    final state = widget.state;
    return [
      if (state.errorMessage != null &&
          state.errorMessage!.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          state.errorMessage!,
          key: const Key('posting-composer-error-message'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  /// metadata 加载中用 SnackBar 轻提示；只有失败态保留正文重试入口。
  Widget _buildMetadataBanner() {
    final state = widget.state;
    final error = state.metadataError;
    if (error != null && error.trim().isNotEmpty) {
      return ComposerStatusBanner.error(
        key: const Key('posting-composer-metadata-error'),
        text: '加载发帖表单失败：$error',
        textKey: const Key('posting-composer-metadata-error-text'),
        retryButtonKey: const Key('posting-composer-metadata-retry-button'),
        onRetry: widget.onRetryLoadMetadata,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMetadataSpacer() {
    final error = widget.state.metadataError;
    if (error != null && error.trim().isNotEmpty) {
      return const SizedBox(height: 12);
    }
    return const SizedBox.shrink();
  }
}

class _PostingMessageEditor extends StatelessWidget {
  const _PostingMessageEditor({
    required this.surface,
    required this.state,
    required this.bbCodeRenderer,
    required this.stickerGroups,
    required this.stickers,
    required this.messageController,
    required this.initialStickerGroupId,
    required this.onStickerGroupChanged,
    required this.onMessageChanged,
    required this.onImagePressed,
  });

  final ComposerSurfacePreference surface;
  final PostingComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerGroup> stickerGroups;
  final List<StickerItem> stickers;
  final TextEditingController messageController;
  final String? initialStickerGroupId;
  final ValueChanged<String> onStickerGroupChanged;
  final ValueChanged<String> onMessageChanged;
  final ComposerImageInsertCallback onImagePressed;

  @override
  Widget build(BuildContext context) {
    final enabled = !state.isSubmitting;
    final renderer = bbCodeRenderer;
    return switch (surface) {
      ComposerSurfacePreference.quill => ComposerQuillEditorSurface(
        key: const Key('posting-composer-quill-editor'),
        keyPrefix: 'posting-composer',
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
        hintText: '请注意上传的图片仅在本地保存24小时',
        expand: true,
        onBbCodeChanged: onMessageChanged,
        messageRevision: state.messageRevision,
        lastMessageMutation: state.lastMessageMutation,
        onImagePressed: onImagePressed,
      ),
      ComposerSurfacePreference.source => ComposerBbCodeSourceEditor(
        keyPrefix: 'posting-composer',
        viewKey: const Key('posting-composer-source-view'),
        inputKey: const Key('posting-composer-message-input'),
        controller: messageController,
        enabled: enabled,
        messageRevision: state.messageRevision,
        onImagePressed: onImagePressed,
        hintText: '请注意上传的图片仅在本地保存24小时',
        onChanged: onMessageChanged,
      ),
    };
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
