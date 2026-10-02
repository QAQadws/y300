import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';
import 'package:y300/shared/widgets/forum_media_loading_style.dart';
import 'package:y300/shared/widgets/forum_metric_pill.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class MyThreadCard extends ConsumerWidget {
  const MyThreadCard({
    super.key,
    required this.item,
    required this.type,
    required this.onOpenThread,
    required this.onOpenReply,
  });

  final UserThreadSummary item;
  final UserThreadDirectoryType type;
  final VoidCallback onOpenThread;
  final ValueChanged<UserThreadReplyPreview> onOpenReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = ThreadDetailNativePalette.resolve(theme);
    final l10n = AppLocalizations.of(context);
    final metadata = [
      item.forumName,
      item.publishedAtText,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final author = item.authorName?.trim() ?? '';
    final excerpt = item.excerpt?.trim() ?? '';
    const radius = BorderRadius.all(Radius.circular(12));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
      ),
      child: Material(
        color: palette.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('my-thread-open-${item.threadId}'),
          onTap: onOpenThread,
          overlayColor: WidgetStatePropertyAll(palette.stateLayer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ForumContentSpacing.postBodyHorizontal,
              ForumContentSpacing.postCardHeaderTop,
              ForumContentSpacing.postBodyHorizontal,
              ForumContentSpacing.postCardSingleBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author.isNotEmpty ||
                    metadata.isNotEmpty ||
                    item.avatarUrl?.trim().isNotEmpty == true) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.avatarUrl?.trim().isNotEmpty == true) ...[
                        ForumCachedAvatar(
                          imageUrl: item.avatarUrl,
                          ownerId: item.authorUserId ?? item.threadId,
                          ownerType: ImageCacheOwnerType.profile,
                          size: 34,
                          imageReferer: ref.watch(forumImageRefererProvider),
                        ),
                        const SizedBox(width: 9),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (author.isNotEmpty)
                              Text(
                                author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: palette.author,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (metadata.isNotEmpty) ...[
                              if (author.isNotEmpty) const SizedBox(height: 2),
                              Text(
                                metadata,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.softText,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                ],
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: palette.title,
                    fontWeight: FontWeight.w800,
                    height: 1.24,
                  ),
                ),
                if (excerpt.isNotEmpty &&
                    (type == UserThreadDirectoryType.threads ||
                        item.replyPreviews.isEmpty)) ...[
                  const SizedBox(height: ForumContentSpacing.postCardBodyTop),
                  Text(
                    excerpt,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.bodyText,
                      height: 1.5,
                    ),
                  ),
                ],
                if (item.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 12) / 3;
                      final images = item.images
                          .take(3)
                          .toList(growable: false);
                      // Allocate the same three slots before any cache lookup
                      // or decode, so loading and fade-out never reflow a row.
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < 3; index++) ...[
                            if (index > 0) const SizedBox(width: 6),
                            Expanded(
                              child: index < images.length
                                  ? _ThreadPreviewImage(
                                      key: ValueKey(images[index]),
                                      threadId: item.threadId,
                                      url: images[index],
                                      size: width,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
                if (type == UserThreadDirectoryType.replies)
                  for (final reply in item.replyPreviews)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Material(
                        color: palette.panelBackground,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('my-thread-reply-${reply.postId}'),
                          onTap: () => onOpenReply(reply),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 18,
                                  color: palette.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    reply.excerpt.trim().isEmpty
                                        ? l10n.profileMyRepliesTab
                                        : reply.excerpt,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: palette.bodyText,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: palette.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                if (item.views != null || item.replies != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      if (item.views != null)
                        ForumMetricPill(
                          icon: Icons.visibility_outlined,
                          label: '${item.views}',
                          semanticsLabel: l10n.profileThreadViews(item.views!),
                          backgroundColor: palette.chipBackground,
                          iconColor: palette.softText,
                          textColor: palette.muted,
                        ),
                      if (item.replies != null)
                        ForumMetricPill(
                          icon: Icons.chat_bubble_outline,
                          label: '${item.replies}',
                          semanticsLabel: l10n.profileThreadReplies(
                            item.replies!,
                          ),
                          backgroundColor: palette.chipBackground,
                          iconColor: palette.softText,
                          textColor: palette.muted,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadPreviewImage extends ConsumerStatefulWidget {
  const _ThreadPreviewImage({
    super.key,
    required this.threadId,
    required this.url,
    required this.size,
  });

  final String threadId;
  final String url;
  final double size;

  @override
  ConsumerState<_ThreadPreviewImage> createState() =>
      _ThreadPreviewImageState();
}

class _ThreadPreviewImageState extends ConsumerState<_ThreadPreviewImage> {
  int _retryToken = 0;

  void _retryImage() => setState(() => _retryToken += 1);

  @override
  Widget build(BuildContext context) {
    final referer = ref.watch(forumImageRefererProvider);
    final uri = Uri.tryParse(widget.url);
    final request = uri == null
        ? null
        : ref
              .watch(forumImageRequestResolverProvider)
              .resolveCacheRequest(
                ForumImageLoadSpec(
                  kind: ForumImageKind.threadInline,
                  url: uri,
                  ownerId: widget.threadId,
                  ownerType: ImageCacheOwnerType.thread,
                  referer: referer,
                  displayWidth: widget.size,
                  displayHeight: widget.size,
                  allowReaderOpen: false,
                ),
              );
    final errorPlaceholder = Container(
      alignment: Alignment.center,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
      child: ImageRetryPlaceholder(
        onRetry: _retryImage,
        retryButtonKey: ValueKey(
          'my-thread-image-retry-${request?.cacheKey ?? widget.url}',
        ),
      ),
    );
    // Reserve geometry without an immediate loading glyph or surface. The
    // shared cache widget shows its indicator only after the loading deadline.
    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedLibraryImage(
          request: request,
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
          placeholder: const SizedBox.expand(),
          errorPlaceholder: errorPlaceholder,
          showDelayedLoadingIndicator: true,
          referer: referer,
          remoteDisplayPolicy: CachedImageRemoteDisplayPolicy.afterCacheWrite,
          fadeInDuration: ForumMediaLoadingStyle.fadeInDuration,
          retryToken: _retryToken,
        ),
      ),
    );
  }
}
