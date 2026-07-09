import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/repositories/profile_blog_repository.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

@immutable
class ProfileBlogListRequest {
  const ProfileBlogListRequest({
    this.view = ProfileBlogView.all,
    this.order = ProfileBlogOrder.latest,
    this.page = 1,
  });

  final ProfileBlogView view;
  final ProfileBlogOrder order;
  final int page;

  ProfileBlogListRequest copyWith({
    ProfileBlogView? view,
    ProfileBlogOrder? order,
    int? page,
  }) {
    return ProfileBlogListRequest(
      view: view ?? this.view,
      order: order ?? this.order,
      page: page ?? this.page,
    );
  }
}

final profileBlogListProvider = FutureProvider.autoDispose
    .family<ProfileBlogListPageData, ProfileBlogListRequest>((
      ref,
      request,
    ) async {
      final result = await ref
          .watch(profileBlogRepositoryProvider)
          .getBlogList(
            view: request.view,
            order: request.order,
            page: request.page,
          );
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

final profileBlogDetailProvider = FutureProvider.autoDispose
    .family<ProfileBlogDetailData, String>((ref, url) async {
      final result = await ref
          .watch(profileBlogRepositoryProvider)
          .getBlogDetail(url: url);
      return switch (result) {
        ApiSuccess(:final data) => data,
        ApiFailure(:final error) => throw error,
      };
    });

class ProfileBlogPage extends ConsumerStatefulWidget {
  const ProfileBlogPage({
    super.key,
    this.initialView = ProfileBlogView.all,
    this.initialOrder = ProfileBlogOrder.latest,
  });

  final ProfileBlogView initialView;
  final ProfileBlogOrder initialOrder;

  @override
  ConsumerState<ProfileBlogPage> createState() => _ProfileBlogPageState();
}

class _ProfileBlogPageState extends ConsumerState<ProfileBlogPage> {
  late ProfileBlogListRequest _request = ProfileBlogListRequest(
    view: widget.initialView,
    order: widget.initialOrder,
  );

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(profileBlogListProvider(_request));
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            tooltip: '写日志',
            onPressed: () => _showTodo('发表新日志暂未接入'),
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
      body: asyncData.when(
        data: (data) => _ProfileBlogListContent(
          data: data,
          request: _request,
          palette: palette,
          imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
          onSelectView: (view) {
            setState(() {
              _request = _request.copyWith(view: view, page: 1);
            });
          },
          onSelectOrder: (order) {
            setState(() {
              _request = _request.copyWith(
                view: ProfileBlogView.all,
                order: order,
                page: 1,
              );
            });
          },
          onOpenBlog: (item) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfileBlogDetailPage(url: item.url),
            ),
          ),
          onLoadNextPage: data.pagination?.nextUrl == null
              ? null
              : () {
                  setState(() {
                    _request = _request.copyWith(page: _request.page + 1);
                  });
                },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ProfileBlogError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(profileBlogListProvider(_request)),
        ),
      ),
    );
  }

  void _showTodo(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class ProfileBlogDetailPage extends ConsumerWidget {
  const ProfileBlogDetailPage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(profileBlogDetailProvider(url));
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: Text(asyncData.value?.title ?? '日志')),
      body: asyncData.when(
        data: (data) => _ProfileBlogDetailContent(
          data: data,
          palette: palette,
          imageHeaderBuilder: imageHeaderBuilder,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ProfileBlogError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(profileBlogDetailProvider(url)),
        ),
      ),
    );
  }
}

class _ProfileBlogListContent extends StatelessWidget {
  const _ProfileBlogListContent({
    required this.data,
    required this.request,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onSelectView,
    required this.onSelectOrder,
    required this.onOpenBlog,
    required this.onLoadNextPage,
  });

  final ProfileBlogListPageData data;
  final ProfileBlogListRequest request;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final ValueChanged<ProfileBlogView> onSelectView;
  final ValueChanged<ProfileBlogOrder> onSelectOrder;
  final ValueChanged<ProfileBlogListItem> onOpenBlog;
  final VoidCallback? onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile-blog-list'),
      padding: EdgeInsets.zero,
      children: [
        _ViewTabs(
          activeView: data.activeView,
          palette: palette,
          onSelect: onSelectView,
        ),
        if (data.activeView == ProfileBlogView.all)
          _OrderTabs(
            activeOrder: data.activeOrder,
            palette: palette,
            onSelect: onSelectOrder,
          ),
        if (data.items.isEmpty)
          _ProfileBlogEmptyState(
            message: data.emptyMessage ?? '还没有相关的日志',
            palette: palette,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              children: [
                for (final item in data.items) ...[
                  _ProfileBlogListCard(
                    key: Key('profile-blog-item-${item.id}'),
                    item: item,
                    palette: palette,
                    imageHeaderBuilder: imageHeaderBuilder,
                    onTap: () => onOpenBlog(item),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        if (data.pagination != null)
          _PaginationBar(
            pagination: data.pagination!,
            palette: palette,
            onLoadNextPage: onLoadNextPage,
          ),
      ],
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.activeView,
    required this.palette,
    required this.onSelect,
  });

  final ProfileBlogView activeView;
  final _ProfileBlogPalette palette;
  final ValueChanged<ProfileBlogView> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.header,
      child: Row(
        key: const Key('profile-blog-view-tabs'),
        children: [
          for (final view in ProfileBlogView.values)
            Expanded(
              child: _TabButton(
                label: view.label,
                selected: activeView == view,
                palette: palette,
                onTap: () => onSelect(view),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderTabs extends StatelessWidget {
  const _OrderTabs({
    required this.activeOrder,
    required this.palette,
    required this.onSelect,
  });

  final ProfileBlogOrder activeOrder;
  final _ProfileBlogPalette palette;
  final ValueChanged<ProfileBlogOrder> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile-blog-order-tabs'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      color: palette.background,
      child: Wrap(
        spacing: 8,
        children: [
          for (final order in ProfileBlogOrder.values)
            ChoiceChip(
              label: Text(order.label),
              selected: activeOrder == order,
              onSelected: (_) => onSelect(order),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _ProfileBlogPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 13, 8, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? palette.accent : palette.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 28 : 0,
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBlogListCard extends StatelessWidget {
  const _ProfileBlogListCard({
    super.key,
    required this.item,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onTap,
  });

  final ProfileBlogListItem item;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProfileBlogAvatar(
                    imageUrl: item.avatarUrl,
                    ownerId: item.author,
                    radius: 17,
                    palette: palette,
                    imageHeaderBuilder: imageHeaderBuilder,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: palette.title,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (item.dateline.isNotEmpty)
                          Text(
                            item.dateline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: palette.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.excerpt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.body,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.palette,
    required this.onLoadNextPage,
  });

  final ProfileBlogPagination pagination;
  final _ProfileBlogPalette palette;
  final VoidCallback? onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '第 ${pagination.currentPage} / ${pagination.totalPages} 页',
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            key: const Key('profile-blog-next-page-button'),
            onPressed: onLoadNextPage,
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }
}

class _ProfileBlogEmptyState extends StatelessWidget {
  const _ProfileBlogEmptyState({required this.message, required this.palette});

  final String message;
  final _ProfileBlogPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 40, color: palette.muted),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: palette.muted)),
          ],
        ),
      ),
    );
  }
}

class _ProfileBlogDetailContent extends StatelessWidget {
  const _ProfileBlogDetailContent({
    required this.data,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final ProfileBlogDetailData data;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile-blog-detail'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _BlogDetailCard(
          data: data,
          palette: palette,
          imageHeaderBuilder: imageHeaderBuilder,
        ),
        if (data.comments.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '日志评论',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final comment in data.comments) ...[
            _CommentCard(
              key: Key('profile-blog-comment-${comment.id}'),
              comment: comment,
              palette: palette,
              imageHeaderBuilder: imageHeaderBuilder,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (data.commentForm != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('profile-blog-comment-placeholder'),
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('日志评论提交暂未接入'))),
            icon: const Icon(Icons.comment_outlined),
            label: const Text('评论'),
          ),
        ],
      ],
    );
  }
}

class _BlogDetailCard extends StatelessWidget {
  const _BlogDetailCard({
    required this.data,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final ProfileBlogDetailData data;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ProfileBlogAvatar(
                imageUrl: data.avatarUrl,
                ownerId: data.author,
                radius: 17,
                palette: palette,
                imageHeaderBuilder: imageHeaderBuilder,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _detailMeta(data),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: palette.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DefaultTextStyle.merge(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.55),
            child: ForumHtmlContentView(
              html: data.messageHtml,
              sourceId: 'profile-blog-${data.id}',
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: data.id,
              contentImageKind: ForumImageKind.blogInline,
              onOpenLink: (url) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(url))),
            ),
          ),
        ],
      ),
    );
  }

  String _detailMeta(ProfileBlogDetailData data) {
    final parts = <String>[
      if (data.author.trim().isNotEmpty) data.author.trim(),
      if (data.dateline.trim().isNotEmpty) data.dateline.trim(),
      '浏览 ${data.views}',
      '评论 ${data.commentsCount}',
    ];
    return parts.join(' · ');
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    super.key,
    required this.comment,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final ProfileBlogComment comment;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileBlogAvatar(
                imageUrl: comment.avatarUrl,
                ownerId: comment.author,
                radius: 15,
                palette: palette,
                imageHeaderBuilder: imageHeaderBuilder,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${comment.author} · ${comment.dateline}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
            child: ForumHtmlContentView(
              html: comment.messageHtml,
              sourceId: 'profile-blog-comment-${comment.id}',
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: comment.id,
              contentImageKind: ForumImageKind.blogInline,
              onOpenLink: (url) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(url))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBlogAvatar extends StatelessWidget {
  const _ProfileBlogAvatar({
    required this.imageUrl,
    required this.ownerId,
    required this.radius,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final String? imageUrl;
  final String ownerId;
  final double radius;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final placeholder = _ProfileBlogAvatarPlaceholder(
      palette: palette,
      iconSize: radius + 1,
    );
    final url = imageUrl?.trim();
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ForumCachedAvatar(
          imageUrl: url,
          ownerId: ownerId.trim().isEmpty ? (url ?? 'unknown') : ownerId,
          ownerType: ImageCacheOwnerType.profile,
          size: size,
          placeholder: placeholder,
          headerBuilder: imageHeaderBuilder,
        ),
      ),
    );
  }
}

class _ProfileBlogAvatarPlaceholder extends StatelessWidget {
  const _ProfileBlogAvatarPlaceholder({
    required this.palette,
    required this.iconSize,
  });

  final _ProfileBlogPalette palette;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.iconBackground,
      child: Center(
        child: Icon(Icons.person, color: palette.accent, size: iconSize),
      ),
    );
  }
}

class _ProfileBlogError extends StatelessWidget {
  const _ProfileBlogError({
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final Object error;
  final _ProfileBlogPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.accent, size: 34),
            const SizedBox(height: 12),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

@immutable
class _ProfileBlogPalette {
  const _ProfileBlogPalette({
    required this.background,
    required this.header,
    required this.card,
    required this.title,
    required this.body,
    required this.muted,
    required this.accent,
    required this.iconBackground,
    required this.border,
    required this.shadow,
  });

  final Color background;
  final Color header;
  final Color card;
  final Color title;
  final Color body;
  final Color muted;
  final Color accent;
  final Color iconBackground;
  final Color border;
  final Color shadow;

  static _ProfileBlogPalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final appBarBackground =
        theme.appBarTheme.backgroundColor ?? scheme.primary;
    if (isDark) {
      return _ProfileBlogPalette(
        background: theme.scaffoldBackgroundColor,
        header: scheme.surfaceContainer,
        card: scheme.surfaceContainerHigh,
        title: scheme.onSurface,
        body: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        iconBackground: scheme.primaryContainer,
        border: scheme.outlineVariant.withValues(alpha: 0.40),
        shadow: Colors.black.withValues(alpha: 0.20),
      );
    }
    return _ProfileBlogPalette(
      background: AppThemeTokens.scaffoldBackground,
      header: AppThemeTokens.forumWebviewSectionBackground,
      card: AppThemeTokens.forumWebviewSectionBackground,
      title: AppThemeTokens.appBarBackground,
      body: const Color(0xFF4F3A2A),
      muted: const Color(0xFF9A8E82),
      accent: appBarBackground,
      iconBackground: appBarBackground.withValues(alpha: 0.10),
      border: appBarBackground.withValues(alpha: 0.08),
      shadow: appBarBackground.withValues(alpha: 0.07),
    );
  }
}

BoxDecoration _cardDecoration(_ProfileBlogPalette palette) {
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: palette.border),
    boxShadow: [
      BoxShadow(
        color: palette.shadow,
        blurRadius: 9,
        offset: const Offset(0, 3),
      ),
    ],
  );
}
