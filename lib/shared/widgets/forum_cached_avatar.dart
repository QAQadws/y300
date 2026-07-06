import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

class ForumCachedAvatar extends ConsumerWidget {
  const ForumCachedAvatar({
    super.key,
    required this.imageUrl,
    required this.ownerId,
    required this.ownerType,
    required this.size,
    this.fit = BoxFit.cover,
    this.shape = BoxShape.circle,
    this.placeholder,
    this.headerBuilder,
  });

  final String? imageUrl;
  final String ownerId;
  final ImageCacheOwnerType ownerType;
  final double size;
  final BoxFit fit;
  final BoxShape shape;
  final Widget? placeholder;
  final ImageRequestHeaderBuilder? headerBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback =
        placeholder ??
        forumDefaultAvatarImage(width: size, height: size, fit: fit);
    final url = imageUrl?.trim();
    final uri = _remoteUriOrNull(url);
    final borderRadius = shape == BoxShape.circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.zero;
    final child = isForumDefaultOrUnsupportedAvatarUrl(url) || uri == null
        ? fallback
        : CachedLibraryImage(
            request: ref
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
                ),
            fit: fit,
            width: size,
            height: size,
            placeholder: fallback,
            errorPlaceholder: fallback,
            headerBuilder: headerBuilder,
          );
    return SizedBox(
      key: const Key('forum-cached-avatar'),
      width: size,
      height: size,
      child: ClipRRect(borderRadius: borderRadius, child: child),
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
