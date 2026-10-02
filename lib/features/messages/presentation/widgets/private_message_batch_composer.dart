import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_sticker_input.dart';
import 'package:y300/features/messages/data/private_message_compose_repository_provider.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';
import 'package:y300/features/messages/presentation/message_command_text.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/message_friend_directory_controller.dart';
import 'package:y300/features/messages/presentation/private_message_batch_send_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_friend_picker_sheet.dart';
import 'package:y300/features/messages/presentation/widgets/message_composer_row.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_batch_result_view.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A route/account-owned draft; only the immutable send snapshot crosses into
/// the command controller. No message or recipient selection is persisted.
class PrivateMessageBatchComposer extends ConsumerStatefulWidget {
  const PrivateMessageBatchComposer({super.key, required this.accountId});
  final String accountId;

  @override
  ConsumerState<PrivateMessageBatchComposer> createState() =>
      _PrivateMessageBatchComposerState();
}

class _PrivateMessageBatchComposerState
    extends ConsumerState<PrivateMessageBatchComposer> {
  final _username = TextEditingController();
  final _selection = PrivateMessageRecipientSelection();
  final _friendControllers = <MessageFriendDirectoryController>{};
  late final PrivateMessageBatchSendController _sender;
  String _message = '';
  AddPrivateMessageRecipientResult? _recipientNotice;
  bool _confirming = false;
  bool _friendSheetOpen = false;
  bool _allowPop = false;
  bool _finishPending = false;

  bool get _ownsAccount =>
      mounted && ref.read(messageAccountIdProvider) == widget.accountId;
  bool get _blocked =>
      _sender.value.isSending || _confirming || _friendSheetOpen;
  bool get _dirty =>
      _message.isNotEmpty || _username.text.isNotEmpty || !_selection.isEmpty;

  @override
  void initState() {
    super.initState();
    _sender = PrivateMessageBatchSendController(
      accountId: widget.accountId,
      currentAccountId: () =>
          mounted ? ref.read(messageAccountIdProvider) : null,
      repository: ref.read(privateMessageComposeRepositoryProvider),
      refreshBus: ref.read(messageRefreshBusProvider),
    )..addListener(_changed);
  }

  void _changed() {
    if (_ownsAccount) setState(() {});
  }

  @override
  void dispose() {
    _sender.removeListener(_changed);
    _sender.dispose();
    for (final controller in _friendControllers) {
      controller.dispose();
    }
    _friendControllers.clear();
    _username.dispose();
    super.dispose();
  }

  bool _addRecipient({bool sending = false}) {
    if (!_ownsAccount || _blocked) return false;
    if (_username.text.isEmpty && sending) return true;
    final result = _selection.addUsername(_username.text);
    setState(() {
      _recipientNotice =
          result == AddPrivateMessageRecipientResult.added ||
              sending && result == AddPrivateMessageRecipientResult.duplicate
          ? null
          : result;
      if (result == AddPrivateMessageRecipientResult.added ||
          result == AddPrivateMessageRecipientResult.duplicate) {
        _username.clear();
      }
    });
    return result == AddPrivateMessageRecipientResult.added ||
        result == AddPrivateMessageRecipientResult.duplicate;
  }

  Future<void> _openFriends() async {
    if (!_ownsAccount || _blocked) return;
    final controller = MessageFriendDirectoryController(
      accountId: widget.accountId,
      currentAccountId: () =>
          mounted ? ref.read(messageAccountIdProvider) : null,
      repository: ref.read(privateMessageComposeRepositoryProvider),
    );
    _friendControllers.add(controller);
    setState(() => _friendSheetOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).y300NativeContent.background,
        builder: (_) => MessageFriendPickerSheet(
          accountId: widget.accountId,
          controller: controller,
          selection: _selection,
          onSelectionChanged: _changed,
        ),
      );
    } finally {
      // Account replacement may have already disposed this route's controller.
      if (_friendControllers.remove(controller)) controller.dispose();
      if (mounted) {
        setState(() => _friendSheetOpen = false);
        if (_finishPending) _finish();
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    if (!_ownsAccount || _confirming) return false;
    setState(() => _confirming = true);
    final l10n = AppLocalizations.of(context);
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
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
    if (!mounted) return false;
    setState(() => _confirming = false);
    if (_finishPending) _finish();
    return accepted && _ownsAccount;
  }

  void _finish() {
    if (!_ownsAccount || _allowPop) return;
    // An applied single send can arrive while the leave dialog owns the top
    // route. Complete the exit after that modal closes, regardless of its choice.
    _finishPending = true;
    if (_confirming || _friendSheetOpen) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownsAccount && (ModalRoute.isCurrentOf(context) ?? false)) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _leave() async {
    if (!_ownsAccount || _confirming) return;
    final l10n = AppLocalizations.of(context);
    if (await _confirm(
      l10n.messageLeaveTitle,
      _sender.value.isSending
          ? l10n.messageLeavePending
          : l10n.messageLeaveBody,
      l10n.messageLeave,
    )) {
      _finish();
    }
  }

  Future<void> _send({bool repeatSnapshot = false}) async {
    if (!_ownsAccount || _blocked) return;
    final previous = _sender.value.snapshot;
    if (repeatSnapshot && previous == null) return;
    if (!repeatSnapshot && !_addRecipient(sending: true)) return;
    final usernames = repeatSnapshot
        ? previous!.usernames
        : _selection.usernameSnapshot();
    final message = repeatSnapshot ? previous!.message : _message;
    if (usernames.isEmpty || message.trim().isEmpty) return;
    var attempt = await _sender.send(usernames: usernames, message: message);
    if (!mounted || !_ownsAccount) return;
    if (attempt == PrivateMessageBatchSendAttempt.confirmationRequired) {
      final l10n = AppLocalizations.of(context);
      final unknown =
          _sender.value.result
              is DataCommandOutcomeUnknown<ForumPrivateMessageBatchReceipt>;
      final confirmed = await _confirm(
        unknown ? l10n.messageSendAgain : l10n.messageBatchRepeatTitle,
        unknown ? l10n.messageUnknownOutcome : l10n.messageBatchRepeatBody,
        l10n.messageSend,
      );
      if (!confirmed) return;
      attempt = await _sender.send(
        usernames: usernames,
        message: message,
        confirmedRepeat: true,
      );
    }
    if (!_ownsAccount || attempt != PrivateMessageBatchSendAttempt.completed) {
      return;
    }
    if (_sender.value.result
        case DataCommandApplied<ForumPrivateMessageBatchReceipt>(
          :final receipt,
        )) {
      if (receipt.confirmsSingleRecipient) {
        setState(() {
          _message = '';
          _username.clear();
          _selection.clear();
        });
        _finish();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _sender.value;
    final applied =
        state.result is DataCommandApplied<ForumPrivateMessageBatchReceipt>;
    return PopScope(
      canPop: _allowPop || !_dirty || applied,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.clamp(0.0, 840.0);
            final receipt = state.result?.receiptOrNull;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child:
                    applied &&
                        receipt != null &&
                        !receipt.confirmsSingleRecipient
                    ? PrivateMessageBatchResultView(
                        snapshot: state.snapshot!,
                        receipt: receipt,
                        onDone: _finish,
                        onSendAgain: _blocked
                            ? null
                            : () => _send(repeatSnapshot: true),
                      )
                    : _form(context, width),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context, double width) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final error = privateMessageCommandText(l10n, _sender.value.result);
    final recipientError = switch (_recipientNotice) {
      AddPrivateMessageRecipientResult.invalid => l10n.messageRecipientInvalid,
      AddPrivateMessageRecipientResult.full =>
        l10n.messageRecipientLimitReached,
      AddPrivateMessageRecipientResult.duplicate =>
        l10n.messageRecipientAlreadySelected,
      _ => null,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.messageRecipientSelectedCount(_selection.length),
            style: TextStyle(color: palette.supportingText),
          ),
          if (!_selection.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final choice in _selection.items)
                    InputChip(
                      key: Key('message-recipient-chip-${choice.username}'),
                      label: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (width - 100).clamp(24.0, 740.0),
                        ),
                        child: Text(choice.username, softWrap: true),
                      ),
                      deleteButtonTooltipMessage: l10n.commonRemove,
                      onDeleted: _blocked
                          ? null
                          : () => setState(() {
                              _selection.remove(choice);
                              _recipientNotice = null;
                            }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('message-recipient'),
                  controller: _username,
                  enabled: !_blocked,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.body,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.messageRecipient,
                    hintText: l10n.messageRecipientHint,
                    errorText: recipientError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _recipientNotice = null),
                  onSubmitted: (_) => _addRecipient(),
                ),
              ),
              IconButton(
                key: const Key('message-recipient-add'),
                tooltip: l10n.messageRecipientAdd,
                onPressed: _blocked ? null : _addRecipient,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('message-friends-open'),
              onPressed: _blocked ? null : _openFriends,
              icon: const Icon(Icons.people_outline),
              label: Text(l10n.messageRecipientChooseFriends),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          MessageComposerRow(
            input: ComposerStickerInput(
              value: _message,
              enabled: !_blocked,
              semanticLabel: l10n.messageInput,
              onChanged: (message) => setState(() => _message = message),
            ),
            busy: _sender.value.isSending,
            onSend: _blocked || _message.trim().isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}
