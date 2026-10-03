import 'package:flutter/material.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/profile/presentation/blog/blog_surface.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

class FriendListRow extends StatelessWidget {
  const FriendListRow({
    super.key,
    required this.item,
    required this.imageReferer,
    this.onOpenUser,
    this.onMessage,
    this.onShowActions,
  });

  final ForumFriendFeedItem item;
  final String imageReferer;
  final VoidCallback? onOpenUser;
  final VoidCallback? onMessage;
  final VoidCallback? onShowActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final note = item.note?.trim() ?? '';
    final visitedAt = item.visitedAtText?.trim() ?? '';
    final avatar = ForumCachedAvatar(
      key: ValueKey((item.userId, item.avatarUrl)),
      imageUrl: item.avatarUrl,
      ownerId: item.userId,
      ownerType: ImageCacheOwnerType.profile,
      imageReferer: imageReferer,
      size: 40,
      fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
    );
    final name = Text(
      item.username.isEmpty ? l10n.profileFriendsAnonymous : item.username,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        color: palette.body,
        fontWeight: FontWeight.w600,
      ),
    );
    return BlogSurface(
      onTap: onMessage,
      onLongPress: onShowActions,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onOpenUser == null)
            avatar
          else
            InkWell(
              key: Key('my-friends-avatar-${item.userId}'),
              onTap: onOpenUser,
              borderRadius: BorderRadius.circular(20),
              child: avatar,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onOpenUser == null)
                  name
                else
                  InkWell(
                    key: Key('my-friends-name-${item.userId}'),
                    onTap: onOpenUser,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: name,
                    ),
                  ),
                if (item.isOnline == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    l10n.profileFriendsOnlineStatus,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.accent,
                    ),
                  ),
                ],
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.supportingText,
                    ),
                  ),
                ],
                if (visitedAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.profileFriendsVisitedAt(visitedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.supportingText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
