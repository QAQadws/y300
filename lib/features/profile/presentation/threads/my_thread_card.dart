import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
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
    final palette = theme.y300NativeContent;
    final l10n = AppLocalizations.of(context);
    final metadata = [
      item.forumName,
      item.authorName,
      item.publishedAtText,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
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
          overlayColor: WidgetStatePropertyAll(palette.subtleStateLayer),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: palette.itemTitle,
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                  ),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.avatarUrl?.trim().isNotEmpty == true) ...[
                        ForumCachedAvatar(
                          imageUrl: item.avatarUrl,
                          ownerId: item.authorUserId ?? item.threadId,
                          ownerType: ImageCacheOwnerType.profile,
                          size: 26,
                          imageReferer: ref.watch(forumImageRefererProvider),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Expanded(
                        child: Text(
                          metadata,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.soft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (excerpt.isNotEmpty &&
                    (type == UserThreadDirectoryType.threads ||
                        item.replyPreviews.isEmpty)) ...[
                  const SizedBox(height: 8),
                  Text(
                    excerpt,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.body,
                      height: 1.4,
                    ),
                  ),
                ],
                if (item.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 12) / 3;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final url in item.images.take(3))
                            _ThreadPreviewImage(
                              threadId: item.threadId,
                              url: url,
                              size: width,
                            ),
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
                        color: palette.subtleStateLayer,
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
                                      color: palette.body,
                                      height: 1.4,
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
                          backgroundColor: palette.subtleStateLayer,
                          iconColor: palette.muted,
                          textColor: palette.supportingText,
                        ),
                      if (item.replies != null)
                        ForumMetricPill(
                          icon: Icons.chat_bubble_outline,
                          label: '${item.replies}',
                          semanticsLabel: l10n.profileThreadReplies(
                            item.replies!,
                          ),
                          backgroundColor: palette.subtleStateLayer,
                          iconColor: palette.muted,
                          textColor: palette.supportingText,
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

class _ThreadPreviewImage extends ConsumerWidget {
  const _ThreadPreviewImage({
    required this.threadId,
    required this.url,
    required this.size,
  });

  final String threadId;
  final String url;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referer = ref.watch(forumImageRefererProvider);
    final uri = Uri.tryParse(url);
    final request = uri == null
        ? null
        : ref
              .watch(forumImageRequestResolverProvider)
              .resolveCacheRequest(
                ForumImageLoadSpec(
                  kind: ForumImageKind.threadInline,
                  url: uri,
                  ownerId: threadId,
                  ownerType: ImageCacheOwnerType.thread,
                  referer: referer,
                  displayWidth: size,
                  displayHeight: size,
                  allowReaderOpen: false,
                ),
              );
    final placeholder = ColoredBox(
      color: ForumMediaLoadingStyle.placeholderColorFor(
        Theme.of(context).y300NativeContent.card,
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).y300NativeContent.muted,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedLibraryImage(
        request: request,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: placeholder,
        errorPlaceholder: placeholder,
        referer: referer,
        remoteDisplayPolicy: CachedImageRemoteDisplayPolicy.afterCacheWrite,
        fadeInDuration: ForumMediaLoadingStyle.fadeInDuration,
      ),
    );
  }
}
