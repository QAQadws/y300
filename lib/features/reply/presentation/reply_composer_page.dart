import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

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
          messageController: _messageController,
          onMessageChanged: controller.updateMessage,
          onUseSignatureChanged: controller.toggleUseSignature,
        ),
      ),
    );
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
}

class _ReplyComposerBody extends StatelessWidget {
  const _ReplyComposerBody({
    required this.state,
    required this.messageController,
    required this.onMessageChanged,
    required this.onUseSignatureChanged,
  });

  final ReplyComposerState state;
  final TextEditingController messageController;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<bool> onUseSignatureChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
