import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_refresh_bus.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/message_command_text.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Ephemeral draft for one route and account. No private text is persisted.
/// Mount with an account key so a session change also discards the old inputs.
class PrivateMessageEditor extends ConsumerStatefulWidget {
  const PrivateMessageEditor({
    super.key,
    required this.accountId,
    required this.onApplied,
    this.recipient,
    this.enabled = true,
  });

  final String accountId;
  final ForumPrivateMessageRecipient? recipient;
  final ValueChanged<ForumPrivateMessageReceipt> onApplied;
  final bool enabled;

  @override
  ConsumerState<PrivateMessageEditor> createState() =>
      _PrivateMessageEditorState();
}

class _PrivateMessageEditorState extends ConsumerState<PrivateMessageEditor> {
  final _text = TextEditingController();
  final _username = TextEditingController();
  ForumRequestCancellation? _cancellation;
  DataCommandResult<ForumPrivateMessageReceipt>? _result;
  bool _busy = false;
  bool _confirming = false;
  bool _allowPop = false;
  bool _invalidRecipient = false;

  bool get _dirty => _text.text.isNotEmpty || _username.text.isNotEmpty;
  bool get _ownsAccount =>
      mounted && ref.read(messageAccountIdProvider) == widget.accountId;

  @override
  void dispose() {
    _cancellation?.cancel();
    _text.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _leave() async {
    if (_confirming) return;
    _confirming = true;
    final l10n = AppLocalizations.of(context);
    final leave = await _confirm(
      l10n.messageLeaveTitle,
      _busy ? l10n.messageLeavePending : l10n.messageLeaveBody,
      l10n.messageLeave,
    );
    if (!mounted) return;
    _confirming = false;
    if (leave) {
      setState(() => _allowPop = true);
      // Let PopScope publish canPop before requesting the actual route pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _send() async {
    if (_busy ||
        _confirming ||
        !widget.enabled ||
        !_ownsAccount ||
        _text.text.trim().isEmpty) {
      return;
    }
    final recipient =
        widget.recipient ??
        ForumPrivateMessageRecipient.username(_username.text.trim());
    if (recipient.kind == ForumPrivateMessageRecipientKind.username &&
        (recipient.value.isEmpty ||
            RegExp(r'[,\x00-\x1f\x7f]').hasMatch(recipient.value))) {
      setState(() => _invalidRecipient = true);
      return;
    }
    if (_result is DataCommandOutcomeUnknown<ForumPrivateMessageReceipt>) {
      _confirming = true;
      final l10n = AppLocalizations.of(context);
      final confirmed = await _confirm(
        l10n.messageSendAgain,
        l10n.messageUnknownOutcome,
        l10n.messageSend,
      );
      if (!mounted) return;
      _confirming = false;
      if (!confirmed || !_ownsAccount) return;
    }
    final repository = ref.read(messageRepositoryProvider);
    final cancellation = _cancellation = ForumRequestCancellation();
    setState(() {
      _busy = true;
      _invalidRecipient = false;
    });
    DataCommandResult<ForumPrivateMessageReceipt> result;
    try {
      result = await repository.send(
        ForumPrivateMessageSubmission(
          recipient: recipient,
          message: _text.text,
          cancellation: cancellation,
        ),
      );
    } on Object {
      // An unexpected throw cannot prove that the server did not receive it.
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'message_send_failed',
          diagnosticMessage: 'message_send_failed',
        ),
      );
    }
    if (!_ownsAccount) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result is DataCommandApplied<ForumPrivateMessageReceipt>) {
        _text.clear();
        _username.clear();
      }
    });
    if (result case DataCommandApplied<ForumPrivateMessageReceipt>(
      :final receipt,
    )) {
      ref
          .read(messageRefreshBusProvider)
          .publish(
            MessageRefreshEvent(
              accountId: widget.accountId,
              kind: MessageRefreshKind.messages,
              target: switch (recipient.kind) {
                ForumPrivateMessageRecipientKind.user =>
                  ForumConversationTarget.direct(recipient.value),
                ForumPrivateMessageRecipientKind.group =>
                  ForumConversationTarget.group(recipient.value),
                ForumPrivateMessageRecipientKind.username => null,
              },
            ),
          );
      widget.onApplied(receipt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = privateMessageCommandText(l10n, _result);
    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.recipient == null) ...[
                  TextField(
                    key: const Key('message-recipient'),
                    controller: _username,
                    readOnly: _busy,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.messageRecipient,
                      hintText: l10n.messageRecipientHint,
                      errorText: _invalidRecipient
                          ? l10n.messageRecipientInvalid
                          : null,
                      errorMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _invalidRecipient = false),
                  ),
                  const SizedBox(height: 12),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                TextField(
                  key: const Key('message-input'),
                  controller: _text,
                  readOnly: _busy,
                  minLines: widget.recipient == null ? 4 : 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.messageInput,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    key: const Key('message-send'),
                    onPressed:
                        _busy || !widget.enabled || _text.text.trim().isEmpty
                        ? null
                        : _send,
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: Text(_busy ? l10n.messageSending : l10n.messageSend),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
