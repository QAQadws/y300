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
  });

  final String accountId;
  final MessageFriendDirectoryController controller;
  final PrivateMessageRecipientSelection selection;
  final VoidCallback onSelectionChanged;

  @override
  ConsumerState<MessageFriendPickerSheet> createState() =>
      _MessageFriendPickerSheetState();
}

class _MessageFriendPickerSheetState
    extends ConsumerState<MessageFriendPickerSheet> {
  late final TextEditingController _search;
  bool _closeScheduled = false;

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
    setState(() {});
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
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          media.size.height * 0.8,
          math.max(0.0, constraints.maxHeight - media.viewInsets.bottom),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: height,
            child: SafeArea(
              top: false,
              child: ValueListenableBuilder<MessageFriendDirectoryState>(
                valueListenable: widget.controller,
                builder: (context, state, _) => Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l10n.messageRecipientChooseFriends,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: palette.itemTitle,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: _close,
                                        tooltip: l10n.commonClose,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    key: const Key('message-friends-search'),
                                    controller: _search,
                                    style: TextStyle(color: palette.body),
                                    onChanged: widget.controller.setSearchQuery,
                                    decoration: InputDecoration(
                                      hintText: l10n.messageFriendSearch,
                                      prefixIcon: const Icon(Icons.search),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.messageRecipientSelectedCount(
                                      widget.selection.length,
                                    ),
                                    style: TextStyle(
                                      color: palette.supportingText,
                                    ),
                                  ),
                                  if (widget.selection.length >=
                                      PrivateMessageRecipientSelection
                                          .maxRecipients)
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
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _emptyStatus(context, state),
                            )
                          else ...[
                            SliverList.builder(
                              itemCount: state.items.length,
                              itemBuilder: (context, index) {
                                final friend = state.items[index];
                                final selected = widget.selection
                                    .containsFriend(
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
                                              onPressed:
                                                  widget.controller.loadMore,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('message-friends-done'),
                          onPressed: _close,
                          child: Text(l10n.messageBatchDone),
                        ),
                      ),
                    ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: state.isBusy
            ? CircularProgressIndicator(color: palette.accent)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
}
