import 'package:y300/app/content_rendering/native_forum_html_render_theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/auth/presentation/login_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_comment_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_actions.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_failure_feedback.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_header.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_metadata.dart';
import 'package:y300/features/profile/presentation/blog/blog_history_visit_observer.dart';
import 'package:y300/features/profile/presentation/blog/blog_surface.dart';
import 'package:y300/features/profile/presentation/blog/blog_scope_pager.dart';
import 'package:y300/features/profile/presentation/blog/blog_text_tabs.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_action_page.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_routes.dart';
import 'package:y300/features/profile/presentation/blog/blog_web_navigation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_view.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_link_navigation.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection_provider.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';

import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/features/profile/presentation/profile_user_link.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';
import 'package:y300/shared/widgets/native_pagination_bar.dart';

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
    final palette = Theme.of(context).y300NativeContent;
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
        body: widget.ownerUserId == null
            ? BlogScopePager(
                key: ObjectKey(controller),
                selectedScope: state.query.scope,
                onSelected: controller.selectScope,
                pageBuilder: (context, scope) => _ProfileBlogFeedPage(
                  controller: controller,
                  state: controller.stateForScope(scope),
                  imageReferer: referer,
                  isActive: widget.isActive && state.query.scope == scope,
                ),
              )
            : _ProfileBlogFeedPage(
                controller: controller,
                state: state,
                imageReferer: referer,
                isActive: widget.isActive,
              ),
      ),
    );
  }
}

class _ProfileBlogFeedPage extends ConsumerWidget {
  const _ProfileBlogFeedPage({
    required this.controller,
    required this.state,
    required this.imageReferer,
    required this.isActive,
  });

  final ProfileBlogPageController controller;
  final UserBlogDirectoryPageState state;
  final String imageReferer;
  final bool isActive;

  // An outgoing page can still receive gestures during the swipe animation.
  // Bind its actions to the query it displays, not the newly selected feed.
  bool get _isCurrent => isActive && controller.value.query == state.query;

  void _whenCurrent(VoidCallback action) {
    if (_isCurrent) action();
  }

  Future<void> _refresh() => _isCurrent ? controller.refresh() : Future.value();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).y300NativeContent;
    return Column(
      children: [
        if (state.query.scope == UserBlogFeedScope.public)
          _OrderTabs(
            activeOrder: state.query.order ?? UserBlogOrder.latest,
            onSelect: (order) =>
                _whenCurrent(() => controller.selectOrder(order)),
          ),
        if (state.categories.isNotEmpty)
          _CategoryFilter(
            query: state.query,
            categories: state.categories,
            onSelect: (category) =>
                _whenCurrent(() => controller.selectCategory(category)),
          ),
        Expanded(
          child: state.data != null
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: _ProfileBlogListContent(
                    key: ValueKey((
                      controller.accountId,
                      state.query.scope,
                      state.query.order,
                      state.query.ownerUserId,
                      state.query.categoryId,
                      state.query.personalCategoryId,
                    )),
                    state: state,
                    accountId: controller.accountId,
                    palette: palette,
                    imageReferer: imageReferer,
                    onOpenBlog: (item) => _whenCurrent(
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileBlogDetailPage(
                            ownerUserId: item.ownerUserId,
                            blogId: item.blogId,
                            initialTitle: item.title,
                          ),
                        ),
                      ),
                    ),
                    onLoadPreviousPage: () =>
                        _whenCurrent(controller.loadPreviousPage),
                    onLoadNextPage: () => _whenCurrent(controller.loadNextPage),
                    onSelectPage: (page) async {
                      // The picker must close before the active route can read.
                      await WidgetsBinding.instance.endOfFrame;
                      if (!context.mounted || !_isCurrent) return;
                      await controller.loadPageNumber(page);
                    },
                    onAction: (item, action) => _whenCurrent(
                      () => action == UserBlogAction.edit
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
                  ),
                )
              : !isActive
              ? const SizedBox.expand()
              : state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _ProfileBlogError(
                  error: state.failure,
                  palette: palette,
                  onRetry: _refresh,
                  onLogin: () => _whenCurrent(
                    () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    ),
                  ),
                  onOpenWeb: () => _whenCurrent(
                    () => openBlogWebPage(
                      context,
                      ref,
                      expectedActor: ref.read(blogAccountIdProvider),
                      destination: (navigation) =>
                          navigation.directory(state.query),
                    ),
                  ),
                ),
        ),
      ],
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
    final palette = Theme.of(context).y300NativeContent;
    final referer = ref.watch(forumImageRefererProvider);
    final l10n = AppLocalizations.of(context);
    return BlogDetailFailureFeedback(
      controller: controller,
      child: BlogHistoryVisitObserver(
        controller: controller,
        child: BlogReadView<UserBlogDetailPageState>(
          key: ObjectKey(controller),
          listenable: controller,
          setActive: controller.setActive,
          builder: (context, state, _) => Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              title: _BlogDetailTitle(
                data: state.data,
                initialTitle: _allowInitialTitle ? widget.initialTitle : null,
              ),
              actions: [
                if (state.data != null &&
                    blogCanReplyToArticle(state.data!, state.capabilities))
                  IconButton(
                    key: const Key('blog-detail-reply'),
                    tooltip: l10n.profileBlogReply,
                    icon: const Icon(Icons.reply),
                    onPressed: () => _openComment(
                      controller,
                      UserBlogCommentAction.add,
                      null,
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
                      onArticleAction: _openArticleAction,
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
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Future<void> _openArticleAction(UserBlogAction action) async {
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
        ref.read(blogAccountIdProvider) == receipt?.target.actorUserId) {
      Navigator.of(context).pop();
    }
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
          refreshOrigin: controller.commentRefreshOrigin,
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
  }
}

class _ProfileBlogListContent extends StatefulWidget {
  const _ProfileBlogListContent({
    super.key,
    required this.state,
    required this.accountId,
    required this.palette,
    required this.imageReferer,
    required this.onOpenBlog,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onSelectPage,
    required this.onAction,
  });

  final UserBlogDirectoryPageState state;
  final String? accountId;
  final Y300NativeContentColors palette;
  final String imageReferer;
  final ValueChanged<UserBlogSummary> onOpenBlog;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onSelectPage;
  final void Function(UserBlogSummary item, UserBlogAction action) onAction;

  @override
  State<_ProfileBlogListContent> createState() =>
      _ProfileBlogListContentState();
}

class _ProfileBlogListContentState extends State<_ProfileBlogListContent> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _ProfileBlogListContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.currentPage == widget.state.currentPage) return;
    final page = widget.state.currentPage;
    // Only a successful page change resets the current feed's scroll position.
    // PageStorage continues to restore the last position when switching tabs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.state.currentPage == page &&
          !widget.state.isLoading &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final palette = widget.palette;
    final data = state.data!;
    final l10n = AppLocalizations.of(context);
    return KeyedSubtree(
      key: const Key('profile-blog-list'),
      child: ListView.builder(
        key: PageStorageKey((
          widget.accountId,
          state.query.scope,
          state.query.order,
          state.query.ownerUserId,
          state.query.categoryId,
          state.query.personalCategoryId,
        )),
        controller: _scrollController,
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
                _PaginationBar(
                  state: state,
                  onLoadPreviousPage: widget.onLoadPreviousPage,
                  onLoadNextPage: widget.onLoadNextPage,
                  onSelectPage: widget.onSelectPage,
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
              imageReferer: widget.imageReferer,
              onTap: () => widget.onOpenBlog(item),
              onAction: (action) => widget.onAction(item, action),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryFilter extends ConsumerWidget {
  const _CategoryFilter({
    required this.query,
    required this.categories,
    required this.onSelect,
  });
  final UserBlogDirectoryQuery query;
  final List<UserBlogCategory> categories;
  final ValueChanged<String?> onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = watchBlogDisplayText(
      ref,
      BlogContentSource(
        text: [for (final category in categories) category.name],
      ),
    );
    final selected = query.categoryId ?? query.personalCategoryId;
    return BlogTextTabs<String?>(
      key: const Key('profile-blog-category-tabs'),
      selectedValue: selected == '0' ? null : selected,
      onSelected: onSelect,
      tabs: [
        BlogTextTab(
          key: const Key('profile-blog-category-all'),
          value: null,
          label: AppLocalizations.of(context).profileBlogAllCategories,
        ),
        for (final category in categories)
          if (category.id != '0')
            BlogTextTab(
              key: Key('profile-blog-category-${category.id}'),
              value: category.id,
              label: display.text(category.name),
            ),
      ],
    );
  }
}

class _OrderTabs extends StatelessWidget {
  const _OrderTabs({required this.activeOrder, required this.onSelect});

  final UserBlogOrder activeOrder;
  final ValueChanged<UserBlogOrder> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlogTextTabs<UserBlogOrder>(
      key: const Key('profile-blog-order-tabs'),
      selectedValue: activeOrder,
      onSelected: onSelect,
      tabs: [
        for (final order in UserBlogOrder.values)
          BlogTextTab(
            key: Key('profile-blog-order-${order.name}'),
            value: order,
            label: ProfileTextResolver.blogOrderShort(l10n, order),
            description: ProfileTextResolver.blogOrder(l10n, order),
          ),
      ],
    );
  }
}

class _ProfileBlogListCard extends ConsumerWidget {
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
  final Y300NativeContentColors palette;
  final String imageReferer;
  final VoidCallback onTap;
  final ValueChanged<UserBlogAction> onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = watchBlogDisplayText(ref, BlogContentSource.summary(item));
    final textTheme = Theme.of(context).textTheme;
    final showAuthor =
        capabilities?.supports(UserBlogDirectoryCapability.author) == true &&
        item.authorName?.isNotEmpty == true;
    final showPublishedAt =
        capabilities?.supports(UserBlogDirectoryCapability.publishedAtText) ==
            true &&
        item.publishedAtText?.trim().isNotEmpty == true;
    return BlogSurface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (capabilities?.supports(
                    UserBlogDirectoryCapability.avatarReference,
                  ) ==
                  true)
                _ProfileBlogAvatar(
                  imageUrl: item.avatarUrl,
                  ownerId: item.ownerUserId,
                  userId: item.ownerUserId,
                  radius: 18,
                  imageReferer: imageReferer,
                  compact: true,
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
                    if (showAuthor)
                      ProfileUserLink(
                        key: Key('blog-list-author-${item.blogId}'),
                        userId: item.ownerUserId,
                        compact: true,
                        child: Text(
                          item.authorName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.author,
                            fontWeight: FontWeight.w700,
                            height: 1.08,
                          ),
                        ),
                      ),
                    if (showPublishedAt) ...[
                      if (showAuthor) const SizedBox(height: 3),
                      Text(
                        display.text(item.publishedAtText!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.muted,
                          fontWeight: FontWeight.w600,
                          height: 1.08,
                        ),
                      ),
                    ],
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
          const SizedBox(height: 7),
          Text(
            display.text(item.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              color: palette.itemTitle,
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
          if (item.categoryNames.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.categoryNames.map(display.text).join(' · '),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.muted),
            ),
          ],
          if (capabilities?.supports(UserBlogDirectoryCapability.excerpt) ==
                  true &&
              item.excerpt != null) ...[
            const SizedBox(height: 6),
            Text(
              display.text(item.excerpt!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.body,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.state,
    required this.onLoadPreviousPage,
    required this.onLoadNextPage,
    required this.onSelectPage,
  });

  final UserBlogDirectoryPageState state;
  final VoidCallback onLoadPreviousPage;
  final VoidCallback onLoadNextPage;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NativePaginationBar(
      key: const Key('profile-blog-pagination'),
      previousButtonKey: const Key('profile-blog-previous-page-button'),
      currentPageButtonKey: const Key('profile-blog-current-page-button'),
      nextButtonKey: const Key('profile-blog-next-page-button'),
      menuKeyPrefix: 'profile-blog',
      currentPage: state.currentPage,
      lastPage: state.lastPage,
      hasMore: state.hasMore,
      canLoadPrevious: state.canLoadPrevious,
      isLoading: state.isLoading,
      onLoadPrevious: onLoadPreviousPage,
      onLoadNext: onLoadNextPage,
      onSelectPage: onSelectPage,
      previousLabel: l10n.commonPreviousPage,
      currentLabel: l10n.commonPage(state.currentPage),
      nextLabel: state.hasMore ? l10n.commonNextPage : l10n.forumDisplayNoMore,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
    );
  }
}

class _ProfileBlogEmptyState extends StatelessWidget {
  const _ProfileBlogEmptyState({required this.message, required this.palette});

  final String message;
  final Y300NativeContentColors palette;

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
    required this.onArticleAction,
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
  final Y300NativeContentColors palette;
  final String imageReferer;
  final void Function(UserBlogCommentAction, UserBlogComment?) onComment;
  final ValueChanged<UserBlogAction> onArticleAction;
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
    final hasComments =
        capabilities?.supports(UserBlogDetailCapability.orderedComments) ==
            true &&
        data.comments.isNotEmpty;
    return CustomScrollView(
      key: const Key('profile-blog-detail'),
      physics: const AlwaysScrollableScrollPhysics(),
      // Content above this origin grows upward. Late article image sizes do
      // not move an initial comment target or require a delayed scroll jump.
      center: focusComments && hasComments ? commentsStart : null,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            ForumContentSpacing.pageHorizontal,
            ForumContentSpacing.listTop,
            ForumContentSpacing.pageHorizontal,
            0,
          ),
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
                onComment: onComment,
                onArticleAction: onArticleAction,
              ),
            ],
          ),
        ),
        SliverPadding(
          key: commentsStart,
          padding: EdgeInsets.fromLTRB(
            ForumContentSpacing.pageHorizontal,
            hasComments ? 12 : 0,
            ForumContentSpacing.pageHorizontal,
            24,
          ),
          sliver: SliverList.list(
            children: [
              if (hasComments) ...[
                Text(
                  key: const Key('profile-blog-comments-heading'),
                  AppLocalizations.of(context).profileBlogComments,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.itemTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final comment in data.comments) ...[
                  _CommentCard(
                    key: Key('profile-blog-comment-${comment.commentId}'),
                    article: data,
                    comment: comment,
                    capabilities: capabilities,
                    palette: palette,
                    imageReferer: imageReferer,
                    onAction: (action) => onComment(action, comment),
                    linkBaseUri: linkBaseUri,
                    onOpenLink: onOpenLink,
                  ),
                  const SizedBox(height: 8),
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
            ],
          ),
        ),
      ],
    );
  }
}

class _BlogDetailTitle extends ConsumerWidget {
  const _BlogDetailTitle({required this.data, required this.initialTitle});
  final UserBlogDetailData? data;
  final String? initialTitle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = data?.title ?? initialTitle;
    if (title == null) {
      return Text(AppLocalizations.of(context).profileBlogTitle);
    }
    final display = watchBlogDisplayText(
      ref,
      data == null
          ? BlogContentSource(text: [title])
          : BlogContentSource.article(data!),
    );
    return Text(display.text(title));
  }
}

class _BlogDetailCard extends ConsumerWidget {
  const _BlogDetailCard({
    required this.data,
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
    required this.linkBaseUri,
    required this.onOpenLink,
    required this.onComment,
    required this.onArticleAction,
  });

  final UserBlogDetailData data;
  final UserBlogDetailReadCapabilities? capabilities;
  final Y300NativeContentColors palette;
  final String imageReferer;
  final Uri? linkBaseUri;
  final ValueChanged<String> onOpenLink;
  final void Function(UserBlogCommentAction, UserBlogComment?) onComment;
  final ValueChanged<UserBlogAction> onArticleAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = watchBlogDisplayText(ref, BlogContentSource.article(data));
    final accountOwner = ref.watch(blogMutationBusProvider);
    final theme = Theme.of(context);
    final date =
        capabilities?.supports(UserBlogDetailCapability.publishedAtText) == true
        ? display.text(data.publishedAtText ?? '').trim()
        : '';
    return BlogContentActions(
      article: data,
      capabilities: capabilities,
      displayHtml: display.html(data.bodyHtml),
      imageReferer: imageReferer,
      linkBaseUri: linkBaseUri,
      onComment: onComment,
      onArticleAction: onArticleAction,
      builder: (onOpenActions) => BlogSurface(
        key: const Key('blog-detail-card'),
        onLongPress: onOpenActions,
        padding: const EdgeInsets.fromLTRB(
          ForumContentSpacing.postBodyHorizontal,
          ForumContentSpacing.postCardHeaderTop,
          ForumContentSpacing.postBodyHorizontal,
          ForumContentSpacing.postCardSingleBottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              display.text(data.title),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.brightness == Brightness.dark
                    ? palette.itemTitle
                    : palette.title,
                fontWeight: FontWeight.w800,
                height: 1.24,
              ),
            ),
            const SizedBox(height: 11),
            BlogDetailHeader(
              viewCount:
                  capabilities?.supports(UserBlogDetailCapability.viewCount) ==
                      true
                  ? data.viewCount
                  : null,
              commentCount:
                  capabilities?.supports(
                        UserBlogDetailCapability.commentCount,
                      ) ==
                      true
                  ? data.commentCount
                  : null,
              author: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      compact: true,
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: _BlogAuthorMetadata(
                      authorKey: const Key('blog-detail-author'),
                      userId: data.ownerUserId,
                      name:
                          capabilities?.supports(
                                UserBlogDetailCapability.author,
                              ) ==
                              true
                          ? data.authorName
                          : null,
                      metadata: date,
                      metadataContent:
                          date.isNotEmpty || data.categoryLinks.isNotEmpty
                          ? BlogDetailMetadata(
                              date: date,
                              categories: [
                                for (final category in data.categoryLinks)
                                  BlogDetailCategoryLink(
                                    key: ValueKey(category.query),
                                    label: display.text(category.name),
                                    onTap: () {
                                      if (!context.mounted ||
                                          ModalRoute.of(context)?.isCurrent ==
                                              false) {
                                        return;
                                      }
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ProfileBlogPage.fromQuery(
                                                category.query,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ForumContentSpacing.postCardBodyTop),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.body,
                height: 1.5,
              ),
              child: ForumHtmlContentView(
                html: display.html(data.bodyHtml),
                sourceId: 'profile-blog-${data.blogId}',
                theme: const ForumHtmlRenderThemeFactory().fromNativeTheme(
                  theme: theme,
                ),
                onOpenImage: (sequence, image) => openBlogImageReader(
                  context,
                  ref,
                  accountOwner: accountOwner,
                  sequence: sequence,
                  image: image,
                  cacheOwnerId: data.blogId,
                  referer: imageReferer,
                ),
                imageReferer: imageReferer,
                imageCacheOwnerId: data.blogId,
                contentImageKind: ForumImageKind.blogInline,
                onOpenLink: onOpenLink,
                linkBaseUri: linkBaseUri,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends ConsumerWidget {
  const _CommentCard({
    super.key,
    required this.article,
    required this.comment,
    required this.capabilities,
    required this.palette,
    required this.imageReferer,
    required this.onAction,
    required this.linkBaseUri,
    required this.onOpenLink,
  });

  final UserBlogDetailData article;
  final UserBlogComment comment;
  final UserBlogDetailReadCapabilities? capabilities;
  final Y300NativeContentColors palette;
  final String imageReferer;
  final ValueChanged<UserBlogCommentAction> onAction;
  final Uri? linkBaseUri;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = watchBlogDisplayText(
      ref,
      BlogContentSource.comment(comment),
    );
    final accountOwner = ref.watch(blogMutationBusProvider);
    return BlogContentActions(
      article: article,
      comment: comment,
      capabilities: capabilities,
      displayHtml: display.html(comment.bodyHtml),
      imageReferer: imageReferer,
      linkBaseUri: linkBaseUri,
      onComment: (action, _) => onAction(action),
      builder: (onOpenActions) => BlogSurface(
        onLongPress: onOpenActions,
        padding: const EdgeInsets.fromLTRB(
          ForumContentSpacing.postBodyHorizontal,
          ForumContentSpacing.postCardHeaderTop,
          ForumContentSpacing.postBodyHorizontal,
          ForumContentSpacing.postCardSingleBottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (capabilities?.supports(
                      UserBlogDetailCapability.commentAvatarReference,
                    ) ==
                    true) ...[
                  _ProfileBlogAvatar(
                    imageUrl: comment.avatarUrl,
                    ownerId: comment.authorUserId ?? comment.authorName,
                    userId: comment.authorUserId,
                    radius: 17,
                    imageReferer: imageReferer,
                    compact: true,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: _BlogAuthorMetadata(
                    authorKey: Key('blog-comment-author-${comment.commentId}'),
                    userId: comment.authorUserId,
                    name: comment.authorName,
                    metadata:
                        capabilities?.supports(
                                  UserBlogDetailCapability
                                      .commentPublishedAtText,
                                ) ==
                                true &&
                            comment.publishedAtText != null
                        ? display.text(comment.publishedAtText!)
                        : '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: ForumContentSpacing.postCardBodyTop),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.body,
                height: 1.5,
              ),
              child: ForumHtmlContentView(
                html: display.html(comment.bodyHtml),
                sourceId: 'profile-blog-comment-${comment.commentId}',
                theme: const ForumHtmlRenderThemeFactory().fromNativeTheme(
                  theme: Theme.of(context),
                ),
                onOpenImage: (sequence, image) => openBlogImageReader(
                  context,
                  ref,
                  accountOwner: accountOwner,
                  sequence: sequence,
                  image: image,
                  cacheOwnerId: comment.commentId,
                  referer: imageReferer,
                ),
                imageReferer: imageReferer,
                imageCacheOwnerId: comment.commentId,
                contentImageKind: ForumImageKind.blogInline,
                onOpenLink: onOpenLink,
                linkBaseUri: linkBaseUri,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlogAuthorMetadata extends StatelessWidget {
  const _BlogAuthorMetadata({
    required this.authorKey,
    required this.userId,
    required this.name,
    required this.metadata,
    this.metadataContent,
  });

  final Key authorKey;
  final String? userId;
  final String? name;
  final String metadata;
  final Widget? metadataContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native = theme.y300NativeContent;
    final showAuthor = name?.trim().isNotEmpty == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAuthor)
          ProfileUserLink(
            key: authorKey,
            userId: userId,
            compact: true,
            child: Text(
              name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: native.author,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (metadata.isNotEmpty || metadataContent != null) ...[
          if (showAuthor) const SizedBox(height: 2),
          metadataContent ??
              Text(
                metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: native.soft,
                  height: 1.1,
                ),
              ),
        ],
      ],
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
    this.compact = false,
  });

  final String? imageUrl;
  final String ownerId;
  final String? userId;
  final double radius;
  final String imageReferer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = imageUrl?.trim();
    return ProfileUserLink(
      userId: userId,
      alignment: Alignment.center,
      compact: compact,
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
  final Y300NativeContentColors palette;
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
              ProfileTextResolver.blogReadError(
                AppLocalizations.of(context),
                error,
              ),
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
