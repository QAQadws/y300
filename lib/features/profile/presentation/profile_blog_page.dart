import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_routes.dart';
import 'package:y300/features/profile/presentation/blog/blog_web_navigation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_view.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_link_navigation.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';

import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/features/profile/presentation/profile_user_link.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

export 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';
export 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
export 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';

class ProfileBlogPage extends ConsumerStatefulWidget {
  const ProfileBlogPage({
    super.key,
    this.initialScope = UserBlogFeedScope.public,
    this.initialOrder = UserBlogOrder.latest,
    this.ownerUserId,
    this.isActive = true,
    this.initialPage = 1,
    this.initialCategoryId,
    this.initialPersonalCategoryId,
  });

  final UserBlogFeedScope initialScope;
  final UserBlogOrder initialOrder;
  final String? ownerUserId;
  final bool isActive;
  final int initialPage;
  final String? initialCategoryId;
  final String? initialPersonalCategoryId;

  factory ProfileBlogPage.fromQuery(UserBlogDirectoryQuery query) =>
      ProfileBlogPage(
        initialScope: query.scope,
        initialOrder: query.order ?? UserBlogOrder.latest,
        ownerUserId: query.ownerUserId,
        initialPage: query.page,
        initialCategoryId: query.categoryId,
        initialPersonalCategoryId: query.personalCategoryId,
      );

  @override
  ConsumerState<ProfileBlogPage> createState() => _ProfileBlogPageState();
}

class _ProfileBlogPageState extends ConsumerState<ProfileBlogPage> {
  @override
  Widget build(BuildContext context) {
    final args = ProfileBlogPageArgs(
      initialScope: widget.initialScope,
      initialOrder: widget.initialOrder,
      ownerUserId: widget.ownerUserId,
      routeOwner: this,
      initialPage: widget.initialPage,
      initialCategoryId: widget.initialCategoryId,
      initialPersonalCategoryId: widget.initialPersonalCategoryId,
    );
    final controller = ref.watch(profileBlogListProvider(args));
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);
    final referer = ref.watch(forumImageRefererProvider);
    return BlogReadView<UserBlogDirectoryPageState>(
      key: ObjectKey(controller),
      listenable: controller,
      setActive: controller.setActive,
      isActive: widget.isActive,
      builder: (context, state, _) => Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          title: Text(l10n.profileBlogTitle),
          actions: [
            IconButton(
              key: const Key('blog-write'),
              tooltip: l10n.profileBlogWrite,
              onPressed: () async {
                final result = await openBlogEditorPage(context, ref);
                if (!mounted ||
                    result == null ||
                    !context.mounted ||
                    ref.read(blogAccountIdProvider) !=
                        result.receipt.target.actorUserId) {
                  return;
                }
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ProfileBlogDetailPage(
                      ownerUserId: result.receipt.target.ownerUserId,
                      blogId: result.receipt.blogId,
                      initialTitle: result.subject,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_note),
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.ownerUserId == null)
              _ViewTabs(
                activeScope: state.query.scope,
                palette: palette,
                onSelect: controller.selectScope,
              ),
            if (state.query.scope == UserBlogFeedScope.public)
              _OrderTabs(
                activeOrder: state.query.order ?? UserBlogOrder.latest,
                palette: palette,
                onSelect: controller.selectOrder,
              ),
            if (state.categories.isNotEmpty)
              _CategoryFilter(
                query: state.query,
                categories: state.categories,
                onSelect: controller.selectCategory,
              ),
            Expanded(
              child: state.data != null
                  ? RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: _ProfileBlogListContent(
                        state: state,
                        accountId: controller.accountId,
                        palette: palette,
                        imageReferer: referer,
                        onOpenBlog: (item) => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProfileBlogDetailPage(
                              ownerUserId: item.ownerUserId,
                              blogId: item.blogId,
                              initialTitle: item.title,
                            ),
                          ),
                        ),
                        onLoadNextPage: state.canLoadNext
                            ? controller.loadNextPage
                            : null,
                        onAction: (item, action) =>
                            action == UserBlogAction.edit
                            ? openBlogEditorPage(
                                context,
                                ref,
                                ownerUserId: item.ownerUserId,
                                blogId: item.blogId,
                              )
                            : openBlogActionPage(
                                context,
                                ref,
                                ownerUserId: item.ownerUserId,
                                blogId: item.blogId,
                                action: action,
                              ),
                      ),
                    )
                  : !widget.isActive
                  ? const SizedBox.expand()
                  : state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _ProfileBlogError(
                      error: state.failure,
                      palette: palette,
                      onRetry: controller.refresh,
                      onLogin: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                      onOpenWeb: () => openBlogWebPage(
                        context,
                        ref,
                        expectedActor: ref.read(blogAccountIdProvider),
                        destination: (navigation) =>
                            navigation.directory(state.query),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileBlogDetailPage extends ConsumerStatefulWidget {
  const ProfileBlogDetailPage({
    super.key,
    required this.ownerUserId,
    required this.blogId,
    this.initialTitle,
    this.initialPage = 1,
    this.commentId,
    this.lastCommentPage = false,
    this.focusComments = false,
  });
  final String ownerUserId;
  final String blogId;
  final String? initialTitle;
  final int initialPage;
  final String? commentId;
  final bool lastCommentPage;
  final bool focusComments;

  @override
  ConsumerState<ProfileBlogDetailPage> createState() =>
      _ProfileBlogDetailPageState();
}

class _ProfileBlogDetailPageState extends ConsumerState<ProfileBlogDetailPage> {
  bool _allowInitialTitle = true;

  @override
  void initState() {
    super.initState();
    final titleActor = ref.read(blogAccountIdProvider);
    ref.listenManual(blogAccountIdProvider, (_, actor) {
      if (actor != titleActor && _allowInitialTitle) {
        setState(() => _allowInitialTitle = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = UserBlogDetailQuery(
      ownerUserId: widget.ownerUserId,
      blogId: widget.blogId,
      page: widget.initialPage,
      commentId: widget.commentId,
      lastCommentPage: widget.lastCommentPage,
    );
    final controller = ref.watch(profileBlogDetailProvider((query, this)));
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));
    final referer = ref.watch(forumImageRefererProvider);
    final l10n = AppLocalizations.of(context);
    return BlogReadView<UserBlogDetailPageState>(
      key: ObjectKey(controller),
      listenable: controller,
      setActive: controller.setActive,
      builder: (context, state, _) => Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          title: Text(
            state.data?.title ??
                (_allowInitialTitle ? widget.initialTitle : null) ??
                l10n.profileBlogTitle,
          ),
          actions: [
            if (state.data != null)
              BlogActionMenu(
                key: const Key('blog-detail-actions'),
                actions: state.data!.actions,
                onSelected: (action) async {
                  if (action == UserBlogAction.edit) {
                    await openBlogEditorPage(
                      context,
                      ref,
                      ownerUserId: widget.ownerUserId,
                      blogId: widget.blogId,
                    );
                    return;
                  }
                  final receipt = await openBlogActionPage(
                    context,
                    ref,
                    ownerUserId: widget.ownerUserId,
                    blogId: widget.blogId,
                    action: action,
                  );
                  if (mounted &&
                      receipt?.target.action == UserBlogAction.delete &&
                      ref.read(blogAccountIdProvider) ==
                          receipt?.target.actorUserId &&
                      context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            if (state.data != null)
              IconButton(
                key: const Key('blog-detail-open-web'),
                tooltip: l10n.profileBlogOpenWeb,
                icon: const Icon(Icons.open_in_browser),
                onPressed: () => openBlogWebPage(
                  context,
                  ref,
                  expectedActor: ref.read(blogAccountIdProvider),
                  destination: (navigation) => navigation.detail(state.query),
                ),
              ),
          ],
        ),
        body: state.data != null
            ? RefreshIndicator(
                onRefresh: controller.refresh,
                child: _ProfileBlogDetailContent(
                  data: state.data!,
                  capabilities: state.capabilities,
                  failure: state.failure,
                  palette: palette,
                  imageReferer: referer,
                  onComment: (action, comment) =>
                      _openComment(controller, action, comment),
                  onLoadNextComments: state.canLoadNext
                      ? controller.loadNextComments
                      : null,
                  onPreviousComments: state.firstCommentPage > 1
                      ? () => controller.selectCommentPage(
                          state.firstCommentPage - 1,
                        )
                      : null,
                  onShowAllComments: state.query.commentId != null
                      ? () => controller.selectCommentPage(1)
                      : null,
                  isLoading: state.isLoading,
                  focusComments: widget.focusComments,
                  linkBaseUri: ref
                      .read(userBlogNavigationProvider)
                      ?.detail(state.query),
                  onOpenLink: (url) => openBlogContentLink(
                    context,
                    ref,
                    url,
                    baseUri: ref
                        .read(userBlogNavigationProvider)
                        ?.detail(state.query),
                  ),
                ),
              )
            : state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _ProfileBlogError(
                error: state.failure,
                palette: palette,
                onRetry: controller.refresh,
                onLogin: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                onOpenWeb: () => openBlogWebPage(
                  context,
                  ref,
                  expectedActor: ref.read(blogAccountIdProvider),
                  destination: (navigation) => navigation.detail(query),
                ),
              ),
      ),
    );
  }

  Future<void> _openComment(
    ProfileBlogDetailController controller,
    UserBlogCommentAction action,
    UserBlogComment? comment,
  ) async {
    final actor = ref.read(blogAccountIdProvider);
    if (actor == null) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    final receipt = await Navigator.of(context).push<UserBlogCommentReceipt>(
      MaterialPageRoute(
        builder: (_) => BlogCommentPage(
          target: UserBlogCommentTarget(
            actorUserId: actor,
            ownerUserId: widget.ownerUserId,
            blogId: widget.blogId,
            action: action,
            commentId: comment?.commentId,
          ),
        ),
      ),
    );
    if (!mounted ||
        receipt == null ||
        ref.read(blogAccountIdProvider) != actor) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (action) {
          UserBlogCommentAction.add ||
          UserBlogCommentAction.reply => l10n.profileBlogCommentSubmitted,
          UserBlogCommentAction.edit => l10n.profileBlogCommentSaved,
          UserBlogCommentAction.delete => l10n.profileBlogCommentDeleted,
        }),
      ),
    );
    // Only a confirmed write refreshes the article. Editing/deleting keeps the
    // current comment range; additions ask the server for its actual last page.
    await controller.refreshAfterComment(action);
  }
}

class _ProfileBlogListContent extends StatelessWidget {
  const _ProfileBlogListContent({
    required this.state,
    required this.accountId,
    required this.palette,
    required this.imageReferer,
    required this.onOpenBlog,
    required this.onLoadNextPage,
    required this.onAction,
  });

  final UserBlogDirectoryPageState state;
  final String? accountId;
  final _ProfileBlogPalette palette;
  final String imageReferer;
  final ValueChanged<UserBlogSummary> onOpenBlog;
  final VoidCallback? onLoadNextPage;
  final void Function(UserBlogSummary item, UserBlogAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final data = state.data!;
    final l10n = AppLocalizations.of(context);
    return KeyedSubtree(
      key: const Key('profile-blog-list'),
      child: ListView.builder(
        key: PageStorageKey((
          accountId,
          state.query.scope,
          state.query.order,
          state.query.ownerUserId,
          state.query.categoryId,
          state.query.personalCategoryId,
        )),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        itemCount: data.items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return state.failure == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.profileBlogLoadFailed(
                        LocalizedErrorSummary.resolve(l10n, state.failure),
                      ),
                      style: TextStyle(color: palette.muted),
                    ),
                  );
          }
          if (index == data.items.length + 1) {
            return Column(
              children: [
                if (data.items.isEmpty)
                  _ProfileBlogEmptyState(
                    message: l10n.profileBlogEmpty,
                    palette: palette,
                  ),
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  )
                else if (state.canLoadNext)
                  _PaginationBar(
                    pagination: data.pagination,
                    palette: palette,
                    onLoadNextPage: onLoadNextPage,
                  ),
              ],
            );
          }
          final item = data.items[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ProfileBlogListCard(
              key: Key('profile-blog-item-${item.blogId}'),
              item: item,
              capabilities: state.capabilities,
              palette: palette,
              imageReferer: imageReferer,
              onTap: () => onOpenBlog(item),
              onAction: (action) => onAction(item, action),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.query,
    required this.categories,
    required this.onSelect,
  });
  final UserBlogDirectoryQuery query;
  final List<UserBlogCategory> categories;
  final ValueChanged<String?> onSelect;
  @override
  Widget build(BuildContext context) {
    final selected = query.categoryId ?? query.personalCategoryId;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                AppLocalizations.of(context).profileBlogAllCategories,
              ),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          for (final category in categories)
            if (category.id != '0')
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category.name),
                  selected: selected == category.id,
                  onSelected: (_) => onSelect(category.id),
                ),
              ),
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.activeScope,
    required this.palette,
    required this.onSelect,
  });

  final UserBlogFeedScope activeScope;
  final _ProfileBlogPalette palette;
  final ValueChanged<UserBlogFeedScope> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.header,
      child: Row(
        key: const Key('profile-blog-view-tabs'),
        children: [
          for (final scope in UserBlogFeedScope.values)
            Expanded(
              child: _TabButton(
                label: ProfileTextResolver.blogView(
                  AppLocalizations.of(context),
                  scope,
                ),
                selected: activeScope == scope,
                palette: palette,
                onTap: () => onSelect(scope),
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

  final UserBlogOrder activeOrder;
  final _ProfileBlogPalette palette;
  final ValueChanged<UserBlogOrder> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile-blog-order-tabs'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      color: palette.background,
      child: Wrap(
        spacing: 8,
        children: [
          for (final order in UserBlogOrder.values)
            ChoiceChip(
              label: Text(
                ProfileTextResolver.blogOrder(
                  AppLocalizations.of(context),
                  order,
                ),
              ),
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
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
    required this.onTap,
    required this.onAction,
  });

  final UserBlogSummary item;
  final UserBlogDirectoryReadCapabilities? capabilities;
  final _ProfileBlogPalette palette;
  final String imageReferer;
  final VoidCallback onTap;
  final ValueChanged<UserBlogAction> onAction;

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
                  if (capabilities?.supports(
                        UserBlogDirectoryCapability.avatarReference,
                      ) ==
                      true)
                    _ProfileBlogAvatar(
                      imageUrl: item.avatarUrl,
                      ownerId: item.ownerUserId,
                      userId: item.ownerUserId,
                      radius: 17,
                      imageReferer: imageReferer,
                    ),
                  if (capabilities?.supports(
                        UserBlogDirectoryCapability.avatarReference,
                      ) ==
                      true)
                    const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (capabilities?.supports(
                                  UserBlogDirectoryCapability.author,
                                ) ==
                                true &&
                            item.authorName != null)
                          ProfileUserLink(
                            key: Key('blog-list-author-${item.blogId}'),
                            userId: item.ownerUserId,
                            child: Text(
                              item.authorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: palette.title,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        if (capabilities?.supports(
                                  UserBlogDirectoryCapability.publishedAtText,
                                ) ==
                                true &&
                            item.publishedAtText != null)
                          Text(
                            item.publishedAtText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.muted),
                          ),
                      ],
                    ),
                  ),
                  BlogActionMenu(
                    key: Key('blog-list-actions-${item.blogId}'),
                    actions: item.actions,
                    onSelected: onAction,
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
              if (capabilities?.supports(UserBlogDirectoryCapability.excerpt) ==
                      true &&
                  item.excerpt != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.excerpt!,
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

  final UserBlogPagination pagination;
  final _ProfileBlogPalette palette;
  final VoidCallback? onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            pagination.totalPages == null
                ? AppLocalizations.of(
                    context,
                  ).commonPage(pagination.currentPage)
                : AppLocalizations.of(context).commonPageOf(
                    pagination.currentPage,
                    pagination.totalPages!,
                  ),
            style: TextStyle(color: palette.muted),
          ),
          FilledButton.tonal(
            key: const Key('profile-blog-next-page-button'),
            onPressed: onLoadNextPage,
            child: Text(AppLocalizations.of(context).commonNextPage),
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
    required this.capabilities,
    required this.failure,
    required this.palette,
    required this.imageReferer,
    required this.onComment,
    required this.onLoadNextComments,
    required this.onPreviousComments,
    required this.onShowAllComments,
    required this.isLoading,
    required this.focusComments,
    required this.linkBaseUri,
    required this.onOpenLink,
  });

  final UserBlogDetailData data;
  final UserBlogDetailReadCapabilities? capabilities;
  final Object? failure;
  final _ProfileBlogPalette palette;
  final String imageReferer;
  final void Function(UserBlogCommentAction, UserBlogComment?) onComment;
  final VoidCallback? onLoadNextComments;
  final VoidCallback? onPreviousComments;
  final VoidCallback? onShowAllComments;
  final bool isLoading;
  final bool focusComments;
  final Uri? linkBaseUri;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    const commentsStart = ValueKey('profile-blog-comments-start');
    return CustomScrollView(
      key: const Key('profile-blog-detail'),
      physics: const AlwaysScrollableScrollPhysics(),
      // Content above this origin grows upward. Late article image sizes do
      // not move an initial comment target or require a delayed scroll jump.
      center: focusComments ? commentsStart : null,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          sliver: SliverList.list(
            children: [
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppLocalizations.of(context).profileBlogLoadFailed(
                      LocalizedErrorSummary.resolve(
                        AppLocalizations.of(context),
                        failure,
                      ),
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              _BlogDetailCard(
                data: data,
                capabilities: capabilities,
                palette: palette,
                imageReferer: imageReferer,
                linkBaseUri: linkBaseUri,
                onOpenLink: onOpenLink,
              ),
            ],
          ),
        ),
        SliverPadding(
          key: commentsStart,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          sliver: SliverList.list(
            children: [
              if (capabilities?.supports(
                    UserBlogDetailCapability.orderedComments,
                  ) ==
                  true) ...[
                Text(
                  key: const Key('profile-blog-comments-heading'),
                  AppLocalizations.of(context).profileBlogComments,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.title,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (data.comments.isEmpty)
                  Text(
                    AppLocalizations.of(context).profileBlogCommentsEmpty,
                    style: TextStyle(color: palette.muted),
                  ),
                for (final comment in data.comments) ...[
                  _CommentCard(
                    key: Key('profile-blog-comment-${comment.commentId}'),
                    comment: comment,
                    capabilities: capabilities,
                    palette: palette,
                    imageReferer: imageReferer,
                    onAction: (action) => onComment(action, comment),
                    linkBaseUri: linkBaseUri,
                    onOpenLink: onOpenLink,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (isLoading) const LinearProgressIndicator(),
              if (onShowAllComments != null ||
                  onLoadNextComments != null ||
                  onPreviousComments != null)
                Wrap(
                  spacing: 8,
                  children: [
                    if (onShowAllComments != null)
                      TextButton(
                        onPressed: onShowAllComments,
                        child: Text(
                          AppLocalizations.of(context).profileBlogAllComments,
                        ),
                      ),
                    if (onPreviousComments != null)
                      TextButton(
                        onPressed: isLoading ? null : onPreviousComments,
                        child: Text(
                          AppLocalizations.of(context).commonPreviousPage,
                        ),
                      ),
                    if (onLoadNextComments != null)
                      TextButton(
                        onPressed: onLoadNextComments,
                        child: Text(
                          AppLocalizations.of(context).profileBlogMoreComments,
                        ),
                      ),
                  ],
                ),
              if (capabilities?.supports(
                        UserBlogDetailCapability.commentingAvailability,
                      ) ==
                      true &&
                  data.commentsOpen == true) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('profile-blog-comment-button'),
                  onPressed: () => onComment(UserBlogCommentAction.add, null),
                  icon: const Icon(Icons.comment_outlined),
                  label: Text(AppLocalizations.of(context).profileBlogComment),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BlogDetailCard extends StatelessWidget {
  const _BlogDetailCard({
    required this.data,
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
    required this.linkBaseUri,
    required this.onOpenLink,
  });

  final UserBlogDetailData data;
  final UserBlogDetailReadCapabilities? capabilities;
  final _ProfileBlogPalette palette;
  final String imageReferer;
  final Uri? linkBaseUri;
  final ValueChanged<String> onOpenLink;

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
              if (capabilities?.supports(
                    UserBlogDetailCapability.avatarReference,
                  ) ==
                  true) ...[
                _ProfileBlogAvatar(
                  imageUrl: data.avatarUrl,
                  ownerId: data.ownerUserId,
                  userId: data.ownerUserId,
                  radius: 17,
                  imageReferer: imageReferer,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ProfileUserLink(
                  key: const Key('blog-detail-author'),
                  userId: data.ownerUserId,
                  child: Text(
                    _detailMeta(context, data),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: palette.muted),
                  ),
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
              html: data.bodyHtml,
              sourceId: 'profile-blog-${data.blogId}',
              imageReferer: imageReferer,
              imageCacheOwnerId: data.blogId,
              contentImageKind: ForumImageKind.blogInline,
              surfaceColor: palette.card,
              foregroundColor: palette.body,
              onOpenLink: onOpenLink,
              linkBaseUri: linkBaseUri,
            ),
          ),
        ],
      ),
    );
  }

  String _detailMeta(BuildContext context, UserBlogDetailData data) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      if (capabilities?.supports(UserBlogDetailCapability.author) == true &&
          data.authorName != null)
        data.authorName!,
      if (capabilities?.supports(UserBlogDetailCapability.publishedAtText) ==
              true &&
          data.publishedAtText != null)
        data.publishedAtText!,
      if (capabilities?.supports(UserBlogDetailCapability.viewCount) == true &&
          data.viewCount != null)
        l10n.profileBlogViews(data.viewCount!),
      if (capabilities?.supports(UserBlogDetailCapability.commentCount) ==
              true &&
          data.commentCount != null)
        l10n.profileBlogCommentCount(data.commentCount!),
    ];
    return parts.join(' · ');
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    super.key,
    required this.comment,
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
    required this.onAction,
    required this.linkBaseUri,
    required this.onOpenLink,
  });

  final UserBlogComment comment;
  final UserBlogDetailReadCapabilities? capabilities;
  final _ProfileBlogPalette palette;
  final String imageReferer;
  final ValueChanged<UserBlogCommentAction> onAction;
  final Uri? linkBaseUri;
  final ValueChanged<String> onOpenLink;

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
              if (capabilities?.supports(
                    UserBlogDetailCapability.commentAvatarReference,
                  ) ==
                  true) ...[
                _ProfileBlogAvatar(
                  imageUrl: comment.avatarUrl,
                  ownerId: comment.authorUserId ?? comment.authorName,
                  userId: comment.authorUserId,
                  radius: 15,
                  imageReferer: imageReferer,
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: ProfileUserLink(
                  key: Key('blog-comment-author-${comment.commentId}'),
                  userId: comment.authorUserId,
                  child: Text(
                    <String>[
                      comment.authorName,
                      if (capabilities?.supports(
                                UserBlogDetailCapability.commentPublishedAtText,
                              ) ==
                              true &&
                          comment.publishedAtText != null)
                        comment.publishedAtText!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (comment.actions.any(
                (action) => action != UserBlogCommentAction.add,
              ))
                PopupMenuButton<UserBlogCommentAction>(
                  key: Key('blog-comment-actions-${comment.commentId}'),
                  tooltip: AppLocalizations.of(context).threadDetailMore,
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    for (final action in UserBlogCommentAction.values)
                      if (action != UserBlogCommentAction.add &&
                          comment.actions.contains(action))
                        PopupMenuItem(
                          value: action,
                          child: Text(
                            blogCommentActionLabel(
                              AppLocalizations.of(context),
                              action,
                            ),
                          ),
                        ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.body, height: 1.45),
            child: ForumHtmlContentView(
              html: comment.bodyHtml,
              sourceId: 'profile-blog-comment-${comment.commentId}',
              imageReferer: imageReferer,
              imageCacheOwnerId: comment.commentId,
              contentImageKind: ForumImageKind.blogInline,
              surfaceColor: palette.card,
              foregroundColor: palette.body,
              onOpenLink: onOpenLink,
              linkBaseUri: linkBaseUri,
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
    required this.userId,
    required this.radius,
    required this.imageReferer,
  });

  final String? imageUrl;
  final String ownerId;
  final String? userId;
  final double radius;
  final String imageReferer;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = imageUrl?.trim();
    return ProfileUserLink(
      userId: userId,
      alignment: Alignment.center,
      child: ForumCachedAvatar(
        imageUrl: url,
        ownerId: ownerId.trim().isEmpty ? (url ?? 'unknown') : ownerId,
        ownerType: ImageCacheOwnerType.profile,
        size: size,
        imageReferer: imageReferer,
      ),
    );
  }
}

class _ProfileBlogError extends StatelessWidget {
  const _ProfileBlogError({
    required this.error,
    required this.palette,
    required this.onRetry,
    required this.onOpenWeb,
    required this.onLogin,
  });

  final Object? error;
  final _ProfileBlogPalette palette;
  final VoidCallback onRetry;
  final VoidCallback onOpenWeb;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: palette.accent, size: 34),
            const SizedBox(height: 12),
            Text(
              _blogReadErrorText(AppLocalizations.of(context), error),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (error case DataReadFailure(
                  kind: DataReadFailureKind.unauthorized,
                ))
                  FilledButton(
                    onPressed: onLogin,
                    child: Text(AppLocalizations.of(context).authLoginTitle),
                  )
                else
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(AppLocalizations.of(context).commonRetry),
                  ),
                TextButton(
                  key: const Key('blog-read-open-web'),
                  onPressed: onOpenWeb,
                  child: Text(AppLocalizations.of(context).profileBlogOpenWeb),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _blogReadErrorText(
  AppLocalizations l10n,
  Object? error,
) => switch (error) {
  DataReadFailure(code: 'user_blog_password_required') =>
    l10n.profileBlogPasswordRequired,
  DataReadFailure(code: 'user_blog_private') => l10n.profileBlogPrivate,
  DataReadFailure(code: 'user_blog_unavailable') => l10n.profileBlogUnavailable,
  DataReadFailure(kind: DataReadFailureKind.unauthorized) =>
    l10n.threadLoginRequired,
  _ => l10n.profileBlogLoadFailed(LocalizedErrorSummary.resolve(l10n, error)),
};

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
    final native = theme.y300NativeContent;
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
      background: native.background,
      header: native.card,
      card: native.card,
      title: native.title,
      body: native.body,
      muted: native.tertiaryText,
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
