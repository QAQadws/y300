import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_media_loading_style.dart';

enum ForumAvatarFallbackPolicy { neutralSurface, localDefaultAvatar }

class ForumCachedAvatar extends ConsumerWidget {
  static const Duration fadeInDuration = ForumMediaLoadingStyle.fadeInDuration;

  const ForumCachedAvatar({
    super.key,
    required this.imageUrl,
    required this.ownerId,
    required this.ownerType,
    required this.size,
    this.headerBuilder,
    this.fallbackPolicy = ForumAvatarFallbackPolicy.neutralSurface,
  });

  final String? imageUrl;
  final String ownerId;
  final ImageCacheOwnerType ownerType;
  final double size;
  final ImageRequestHeaderBuilder? headerBuilder;
  final ForumAvatarFallbackPolicy fallbackPolicy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fallback = ColoredBox(
      key: const Key('forum-avatar-placeholder'),
      color: ForumMediaLoadingStyle.placeholderColorFor(
        theme.scaffoldBackgroundColor,
      ),
    );
    final localDefaultAvatar = _buildLocalDefaultAvatar(fallback);
    final unavailableAvatar =
        fallbackPolicy == ForumAvatarFallbackPolicy.localDefaultAvatar
        ? localDefaultAvatar
        : fallback;
    final url = imageUrl?.trim();
    final uri = _remoteUriOrNull(url);
    final isDefaultAvatar = isForumDefaultAvatarUrl(url);
    final canLoadRemote =
        !isForumDefaultOrUnsupportedAvatarUrl(url) && uri != null;
    final request = canLoadRemote
        ? ref
              .watch(forumImageRequestResolverProvider)
              .resolveCacheRequest(
                ForumImageLoadSpec(
                  kind: ForumImageKind.avatar,
                  url: uri,
                  ownerId: ownerId.trim().isEmpty ? url : ownerId.trim(),
                  ownerType: ownerType,
                  displayWidth: size,
                  displayHeight: size,
                  allowReaderOpen: false,
                ),
              )
        : null;
    final child = isDefaultAvatar
        ? localDefaultAvatar
        : request != null
        ? CachedLibraryImage(
            request: request,
            fit: BoxFit.cover,
            width: size,
            height: size,
            placeholder: fallback,
            errorPlaceholder: unavailableAvatar,
            headerBuilder: headerBuilder,
            fadeInDuration: ForumMediaLoadingStyle.fadeInDuration,
          )
        : unavailableAvatar;
    return SizedBox(
      key: const Key('forum-cached-avatar'),
      width: size,
      height: size,
      child: ClipOval(child: child),
    );
  }

  static Color placeholderColorFor(Color backgroundColor) {
    return ForumMediaLoadingStyle.placeholderColorFor(backgroundColor);
  }

  Widget _buildLocalDefaultAvatar(Widget placeholder) {
    return CachedLibraryImage(
      request: null,
      imageProviderOverride: const AssetImage(forumDefaultAvatarAsset),
      fit: BoxFit.cover,
      width: size,
      height: size,
      placeholder: placeholder,
      errorPlaceholder: placeholder,
      fadeInDuration: ForumMediaLoadingStyle.fadeInDuration,
    );
  }

  Uri? _remoteUriOrNull(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? uri : null;
  }
}
