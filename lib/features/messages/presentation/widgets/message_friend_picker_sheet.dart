import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';
import 'package:y300/features/messages/presentation/message_feed_providers.dart';
import 'package:y300/features/messages/presentation/message_friend_directory_controller.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';
import 'package:y300/l10n/app_localizations.dart';

/// The caller disposes [controller] when this sheet closes. Selection belongs
/// to the compose route, so closing or filtering never discards recipients.
class MessageFriendPickerSheet extends ConsumerStatefulWidget {
  const MessageFriendPickerSheet({
    super.key,
    required this.accountId,
    required this.controller,
    required this.selection,
    required this.onSelectionChanged,
    this.allowManualRecipients = false,
  });

  final String accountId;
  final MessageFriendDirectoryController controller;
  final PrivateMessageRecipientSelection selection;
  final VoidCallback onSelectionChanged;
  final bool allowManualRecipients;

  @override
  ConsumerState<MessageFriendPickerSheet> createState() =>
      _MessageFriendPickerSheetState();
}

class _MessageFriendPickerSheetState
    extends ConsumerState<MessageFriendPickerSheet> {
  late final TextEditingController _search;
  bool _closeScheduled = false;
  AddPrivateMessageRecipientResult? _recipientNotice;

  bool get _ownsAccount =>
      mounted && ref.read(messageAccountIdProvider) == widget.accountId;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.value.query);
    unawaited(widget.controller.initialize());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
      Navigator.of(context).pop();
    }
  }

  void _toggle(ForumFriendDirectoryItem friend) {
    if (!_ownsAccount) return;
    final selection = widget.selection;
    final selected = selection.containsFriend(friend.userId, friend.username);
    final changed = selected
        ? selection.remove(
            PrivateMessageRecipientChoice(
              username: friend.username,
              userId: friend.userId,
            ),
          )
        : selection.addFriend(
                userId: friend.userId,
                username: friend.username,
              ) ==
              AddPrivateMessageRecipientResult.added;
    if (!changed) return;
    setState(() => _recipientNotice = null);
    widget.onSelectionChanged();
  }

  void _addUsername() {
    if (!_ownsAccount || !widget.allowManualRecipients) return;
    final result = widget.selection.addUsername(_search.text);
    setState(() => _recipientNotice = result);
    if (result == AddPrivateMessageRecipientResult.added ||
        result == AddPrivateMessageRecipientResult.duplicate) {
      _search.clear();
      widget.controller.setSearchQuery('');
    }
    if (result == AddPrivateMessageRecipientResult.added) {
      widget.onSelectionChanged();
    }
  }

  void _remove(PrivateMessageRecipientChoice choice) {
    if (!_ownsAccount || !widget.selection.remove(choice)) return;
    setState(() => _recipientNotice = null);
    widget.onSelectionChanged();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(messageAccountIdProvider);
    if (account != widget.accountId) {
      if (!_closeScheduled) {
        _closeScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      }
      // Do not paint the previous owner's names during the closing frame.
      return const SizedBox.shrink();
    }
    final palette = Theme.of(context).y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bound content by the route's actual space above the keyboard so a
        // dismissible area remains even in split-screen or constrained hosts.
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - media.viewInsets.bottom,
        );
        final height = math.min(availableHeight * 0.6, 520.0);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: SafeArea(
              top: false,
              child: ValueListenableBuilder<MessageFriendDirectoryState>(
                valueListenable: widget.controller,
                builder: (context, state, _) => CustomScrollView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _searchField(context),
                            const SizedBox(height: 12),
                            Text(
                              l10n.messageRecipientSelectedCount(
                                widget.selection.length,
                              ),
                              style: TextStyle(color: palette.supportingText),
                            ),
                            if (widget.allowManualRecipients &&
                                !widget.selection.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final choice
                                          in widget.selection.items) ...[
                                        InputChip(
                                          key: Key(
                                            'message-recipient-chip-${choice.username}',
                                          ),
                                          label: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: math.max(
                                                48,
                                                constraints.maxWidth - 112,
                                              ),
                                            ),
                                            child: Text(
                                              choice.username,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          deleteButtonTooltipMessage:
                                              l10n.commonRemove,
                                          deleteIcon: const Icon(
                                            Icons.remove,
                                            size: 16,
                                          ),
                                          backgroundColor: palette.accent
                                              .withValues(alpha: 0.08),
                                          side: BorderSide.none,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          labelStyle: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: palette.accent),
                                          onDeleted: () => _remove(choice),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            if (widget.selection.length >=
                                PrivateMessageRecipientSelection.maxRecipients)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  l10n.messageRecipientLimitReached,
                                  style: TextStyle(
                                    color: palette.supportingText,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (state.items.isEmpty)
                      SliverToBoxAdapter(child: _emptyStatus(context, state))
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        sliver: SliverList.builder(
                          itemCount: state.items.length,
                          itemBuilder: (context, index) {
                            final friend = state.items[index];
                            final selected = widget.selection.containsFriend(
                              friend.userId,
                              friend.username,
                            );
                            final enabled =
                                selected ||
                                widget.selection.length <
                                    PrivateMessageRecipientSelection
                                        .maxRecipients;
                            return CheckboxListTile(
                              key: Key('message-friend-${friend.userId}'),
                              value: selected,
                              selected: selected,
                              activeColor: palette.accent,
                              checkColor: palette.onAccent,
                              checkboxShape: const CircleBorder(),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              selectedTileColor: palette.accent.withValues(
                                alpha: 0.08,
                              ),
                              onChanged: enabled
                                  ? (_) => _toggle(friend)
                                  : null,
                              title: Text(
                                friend.username,
                                style: TextStyle(color: palette.body),
                              ),
                              secondary: MessageAvatar(
                                userId: friend.userId,
                                imageUrl: friend.avatarUrl,
                              ),
                            );
                          },
                        ),
                      ),
                      if (state.hasMore || state.failure != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: state.isBusy
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: palette.accent,
                                    ),
                                  )
                                : Column(
                                    children: [
                                      if (state.failure != null)
                                        Text(
                                          l10n.messageFriendLoadFailed,
                                          style: TextStyle(
                                            color: palette.supportingText,
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: widget.controller.loadMore,
                                        child: Text(
                                          state.failure != null
                                              ? l10n.commonRetry
                                              : l10n.messageLoadMore,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyStatus(BuildContext context, MessageFriendDirectoryState state) {
    final palette = Theme.of(context).y300NativeContent;
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 124),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: state.isBusy
            ? Center(
                heightFactor: 1,
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(color: palette.accent),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    state.failure != null
                        ? Icons.wifi_off_outlined
                        : Icons.people_outline,
                    size: 26,
                    color: palette.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.failure != null
                        ? l10n.messageFriendLoadFailed
                        : state.query.isEmpty
                        ? l10n.messageFriendEmpty
                        : l10n.messageFriendNoMatches,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.supportingText),
                  ),
                  if (state.failure != null)
                    TextButton(
                      onPressed: widget.controller.refresh,
                      child: Text(l10n.commonRetry),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = Theme.of(context).y300NativeContent;
    final error = switch (_recipientNotice) {
      AddPrivateMessageRecipientResult.invalid => l10n.messageRecipientInvalid,
      AddPrivateMessageRecipientResult.full =>
        l10n.messageRecipientLimitReached,
      AddPrivateMessageRecipientResult.duplicate =>
        l10n.messageRecipientAlreadySelected,
      _ => null,
    };
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return KeyedSubtree(
      key: const Key('message-friends-search'),
      child: TextField(
        key: widget.allowManualRecipients
            ? const Key('message-recipient')
            : null,
        controller: _search,
        style: TextStyle(color: palette.body),
        autocorrect: false,
        textInputAction: widget.allowManualRecipients
            ? TextInputAction.done
            : TextInputAction.search,
        onChanged: (query) {
          setState(() => _recipientNotice = null);
          widget.controller.setSearchQuery(query);
        },
        onSubmitted: widget.allowManualRecipients
            ? (_) => _addUsername()
            : null,
        decoration: InputDecoration(
          hintText: widget.allowManualRecipients
              ? l10n.messageRecipientSearchHint
              : l10n.messageFriendSearch,
          isDense: true,
          filled: true,
          fillColor: palette.body.withValues(alpha: 0.045),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: palette.accent),
          ),
          prefixIcon: Icon(Icons.search, size: 20, color: palette.muted),
          suffixIcon: widget.allowManualRecipients
              ? IconButton(
                  key: const Key('message-recipient-add'),
                  tooltip: l10n.messageRecipientAdd,
                  color: palette.accent,
                  onPressed: _addUsername,
                  icon: const Icon(Icons.add),
                )
              : null,
          errorText: error,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}
