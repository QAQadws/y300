import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

enum MessageAvatarKind { user, group, system }

class MessageAvatar extends ConsumerWidget {
  const MessageAvatar({
    super.key,
    this.kind = MessageAvatarKind.user,
    this.userId = '',
    this.imageUrl,
    this.size = 40,
  });

  final MessageAvatarKind kind;
  final String userId;
  final String? imageUrl;
  final double size;

  static const groupAsset = 'assets/messages/grouppm.png';
  static const systemAsset = 'assets/messages/systempm.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kind == MessageAvatarKind.user) {
      return ForumCachedAvatar(
        // Changing identities must not retain another user's decoded frame.
        key: ValueKey((userId, imageUrl)),
        imageUrl: imageUrl,
        ownerId: userId,
        ownerType: ImageCacheOwnerType.profile,
        imageReferer: ref.watch(forumImageRefererProvider),
        size: size,
        fallbackPolicy: ForumAvatarFallbackPolicy.localDefaultAvatar,
      );
    }
    final palette = Theme.of(context).y300NativeContent;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: palette.avatarBackground,
          child: Padding(
            padding: EdgeInsets.all(size / 10),
            child: Image.asset(
              kind == MessageAvatarKind.group ? groupAsset : systemAsset,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}
