import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_content_action_sheet.dart';

enum FriendAction { message, remove }

@immutable
final class FriendActionTarget {
  const FriendActionTarget({
    required this.owner,
    required this.scope,
    required this.page,
    required this.userId,
  });

  final VerifiedProfileOwner owner;
  final ForumFriendFeedScope scope;
  final int page;
  final String userId;
}

/// A sheet keeps its original owner and row identity even while covering the
/// source route. The caller validates route activity after the sheet closes.
class FriendActionSheet extends ConsumerStatefulWidget {
  const FriendActionSheet({
    super.key,
    required this.target,
    required this.controller,
    required this.isTargetAttached,
  });

  final FriendActionTarget target;
  final MyFriendsController controller;
  final bool Function() isTargetAttached;

  @override
  ConsumerState<FriendActionSheet> createState() => _FriendActionSheetState();
}

class _FriendActionSheetState extends ConsumerState<FriendActionSheet> {
  bool _dismissScheduled = false;

  Widget _dismiss() {
    if ((ModalRoute.isCurrentOf(context) ?? false) && !_dismissScheduled) {
      _dismissScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dismissScheduled = false;
        if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
          Navigator.of(context).pop();
        }
      });
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    if (owner != widget.target.owner || !widget.isTargetAttached()) {
      return _dismiss();
    }
    return ValueListenableBuilder<MyFriendsPageState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        if (!widget.isTargetAttached()) return _dismiss();
        final item = state.data!.items.firstWhere(
          (item) => item.userId == widget.target.userId,
        );
        final l10n = AppLocalizations.of(context);
        return ForumContentActionSheet<FriendAction>(
          key: const Key('my-friends-actions-sheet'),
          actions: [
            ForumContentAction(
              key: Key('my-friends-message-${item.userId}'),
              value: FriendAction.message,
              label: l10n.profilePrivateMessage,
              icon: Icons.chat_bubble_outline,
            ),
            if (widget.target.scope == ForumFriendFeedScope.friends &&
                item.canRemove &&
                !state.isLoading &&
                !state.isRemoving &&
                !state.unverifiedRemovalUserIds.contains(item.userId))
              ForumContentAction(
                key: Key('my-friends-remove-${item.userId}'),
                value: FriendAction.remove,
                label: l10n.profileFriendRemove,
                icon: Icons.person_remove_outlined,
              ),
          ],
        );
      },
    );
  }
}
