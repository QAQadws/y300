import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/reply/presentation/widgets/bbcode_preview_panel.dart';
import 'package:y300/features/reply/presentation/widgets/reply_editor_toolbar.dart';
import 'package:y300/features/reply/presentation/widgets/sticker_picker_sheet.dart';

class ReplyComposerPage extends ConsumerStatefulWidget {
  const ReplyComposerPage({
    super.key,
    required this.args,
  });

  final ReplyComposerArgs args;

  @override
  ConsumerState<ReplyComposerPage> createState() => _ReplyComposerPageState();
}

class _ReplyComposerPageState extends ConsumerState<ReplyComposerPage> {
  late final TextEditingController _messageController;
  ReplyComposerController? _controller;
  bool _didApplyRestoredDraft = false;

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
    final stickerGroups = ref.watch(stickerGroupsProvider).maybeWhen(
          data: (groups) => groups,
          orElse: () => const <StickerGroup>[],
        );
    _controller = controller;
    final state = asyncState.value;
    if (state != null) {
      _applyRestoredDraftOnce(state);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('回复帖子'),
        actions: [
          IconButton(
            key: const Key('reply-composer-send-button'),
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
        error: (error, _) => _ReplyComposerErrorView(
          message: '加载草稿失败：$error',
        ),
        data: (state) => _ReplyComposerBody(
          state: state,
          bbCodeRenderer: bbCodeRenderer,
          stickers: _flattenStickers(stickerGroups),
          messageController: _messageController,
          onModeChanged: controller.switchMode,
          onMessageChanged: controller.updateMessage,
          onUseSignatureChanged: controller.toggleUseSignature,
          onStickerPressed: () {
            unawaited(_pickAndInsertSticker(context, controller));
          },
        ),
      ),
    );
  }

  List<StickerItem> _flattenStickers(List<StickerGroup> groups) {
    return [
      for (final group in groups) ...group.stickers,
    ];
  }

  void _applyRestoredDraftOnce(ReplyComposerState state) {
    if (_didApplyRestoredDraft) {
      return;
    }
    _didApplyRestoredDraft = true;
    _messageController.value = TextEditingValue(
      text: state.message,
      selection: TextSelection.collapsed(offset: state.message.length),
    );
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
    navigator.pop(result);
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

  void _insertSticker(
    StickerItem sticker,
    ReplyComposerController controller,
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
  }
}

class _ReplyComposerBody extends StatelessWidget {
  const _ReplyComposerBody({
    required this.state,
    required this.bbCodeRenderer,
    required this.stickers,
    required this.messageController,
    required this.onModeChanged,
    required this.onMessageChanged,
    required this.onUseSignatureChanged,
    required this.onStickerPressed,
  });

  final ReplyComposerState state;
  final ForumBbCodeRenderer bbCodeRenderer;
  final List<StickerItem> stickers;
  final TextEditingController messageController;
  final ValueChanged<ReplyComposerMode> onModeChanged;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<bool> onUseSignatureChanged;
  final VoidCallback onStickerPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ReplyComposerMode>(
              key: const Key('reply-composer-mode-switch'),
              segments: const [
                ButtonSegment<ReplyComposerMode>(
                  value: ReplyComposerMode.source,
                  label: Text('源码'),
                  icon: Icon(Icons.edit_note),
                ),
                ButtonSegment<ReplyComposerMode>(
                  value: ReplyComposerMode.preview,
                  label: Text('预览'),
                  icon: Icon(Icons.visibility),
                ),
              ],
              selected: {state.mode},
              onSelectionChanged: state.isSubmitting
                  ? null
                  : (selection) {
                      onModeChanged(selection.single);
                    },
            ),
          ),
          const SizedBox(height: 12),
          ReplyEditorToolbar(
            enabled: !state.isSubmitting,
            onStickerPressed: onStickerPressed,
          ),
          const SizedBox(height: 12),
          if (state.mode == ReplyComposerMode.source)
            TextField(
              key: const Key('reply-composer-message-input'),
              controller: messageController,
              enabled: !state.isSubmitting,
              minLines: 8,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: onMessageChanged,
              decoration: const InputDecoration(
                hintText: '输入回复内容',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            )
          else
            BbCodePreviewPanel(
              source: state.message,
              renderer: bbCodeRenderer,
              stickers: stickers,
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('reply-composer-use-signature-switch'),
            value: state.useSignature,
            onChanged: state.isSubmitting ? null : onUseSignatureChanged,
            title: const Text('使用个人签名'),
            contentPadding: EdgeInsets.zero,
          ),
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

class _ReplyComposerErrorView extends StatelessWidget {
  const _ReplyComposerErrorView({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          key: const Key('reply-composer-load-error'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
