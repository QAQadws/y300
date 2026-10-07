import 'dart:math' as math;

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
import 'package:y300/features/messages/presentation/widgets/private_message_compose_canvas.dart';
import 'package:y300/features/messages/presentation/widgets/private_message_recipient_bar.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

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
  final _selection = PrivateMessageRecipientSelection();
  final _friendControllers = <MessageFriendDirectoryController>{};
  late final PrivateMessageBatchSendController _sender;
  String _message = '';
  bool _confirming = false;
  bool _friendSheetOpen = false;
  bool _allowPop = false;
  bool _finishPending = false;

  bool get _ownsAccount =>
      mounted && ref.read(messageAccountIdProvider) == widget.accountId;
  bool get _blocked =>
      _sender.value.isSending || _confirming || _friendSheetOpen;
  bool get _dirty => _message.isNotEmpty || !_selection.isEmpty;

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
    super.dispose();
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
        showDragHandle: false,
        backgroundColor: Theme.of(context).y300NativeContent.background,
        builder: (_) => MessageFriendPickerSheet(
          accountId: widget.accountId,
          controller: controller,
          selection: _selection,
          onSelectionChanged: _changed,
          allowManualRecipients: true,
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
                    : _form(context, constraints.maxHeight),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context, double height) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final error = privateMessageCommandText(l10n, _sender.value.result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: PrivateMessageRecipientBar(
                  selection: _selection,
                  onPressed: _blocked ? null : _openFriends,
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: PrivateMessageComposeCanvas(
                  hasRecipients: !_selection.isEmpty,
                  error: error,
                ),
              ),
            ],
          ),
        ),
        // Keep the input mounted outside the scrollable canvas. Scaffold owns
        // keyboard avoidance; only the editor's internal viewport may shrink.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(height, math.max(80, height * 0.55)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
              ),
              child: Material(
                key: const Key('message-compose-dock'),
                color: palette.card,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: MessageComposerRow(
                    input: ComposerStickerInput(
                      value: _message,
                      enabled: !_blocked,
                      semanticLabel: l10n.messageInput,
                      inputBorder: InputBorder.none,
                      onChanged: (message) =>
                          setState(() => _message = message),
                    ),
                    emphasized: true,
                    busy: _sender.value.isSending,
                    onSend:
                        _blocked ||
                            _selection.isEmpty ||
                            _message.trim().isEmpty
                        ? null
                        : _send,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
