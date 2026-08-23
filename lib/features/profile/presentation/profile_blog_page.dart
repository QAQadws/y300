import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';
import 'package:y300/features/profile/presentation/profile_text_resolver.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_content_view.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';

@immutable
final class ProfileBlogPageArgs {
  const ProfileBlogPageArgs({
    this.initialScope = UserBlogFeedScope.public,
    this.initialOrder = UserBlogOrder.latest,
  });

  final UserBlogFeedScope initialScope;
  final UserBlogOrder initialOrder;

  @override
  bool operator ==(Object other) {
    return other is ProfileBlogPageArgs &&
        other.initialScope == initialScope &&
        other.initialOrder == initialOrder;
  }

  @override
  int get hashCode => Object.hash(initialScope, initialOrder);
}

final class UserBlogDirectoryPageState {
  const UserBlogDirectoryPageState({
    required this.query,
    this.data,
    this.capabilities,
    this.metadata,
    this.failure,
    this.isLoading = false,
  });

  final UserBlogDirectoryQuery query;
  final UserBlogDirectoryData? data;
  final UserBlogDirectoryReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final DataReadFailure<
    UserBlogDirectoryData,
    UserBlogDirectoryReadCapabilities
  >?
  failure;
  final bool isLoading;

  UserBlogDirectoryPageState copyWith({
    UserBlogDirectoryQuery? query,
    UserBlogDirectoryData? data,
    UserBlogDirectoryReadCapabilities? capabilities,
    DataReadMetadata? metadata,
    DataReadFailure<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>?
    failure,
    bool? isLoading,
    bool clearFailure = false,
  }) {
    return UserBlogDirectoryPageState(
      query: query ?? this.query,
      data: data ?? this.data,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      failure: clearFailure ? null : (failure ?? this.failure),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final profileBlogListProvider = AsyncNotifierProvider.autoDispose
    .family<
      ProfileBlogPageController,
      UserBlogDirectoryPageState,
      ProfileBlogPageArgs
    >((args) => ProfileBlogPageController(args));

final class ProfileBlogPageController
    extends AsyncNotifier<UserBlogDirectoryPageState> {
  ProfileBlogPageController(this._args);

  final ProfileBlogPageArgs _args;

  @override
  Future<UserBlogDirectoryPageState> build() {
    final query = _queryFor(
      scope: _args.initialScope,
      order: _args.initialOrder,
    );
    return _load(
      query,
      previous: null,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
  }

  Future<void> refresh() async {
    final previous = state.value;
    if (previous == null) {
      return;
    }
    state = AsyncData(previous.copyWith(isLoading: true, clearFailure: true));
    state = AsyncData(
      await _load(
        previous.query,
        previous: previous,
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<void> selectScope(UserBlogFeedScope scope) async {
    final previous = state.value;
    if (previous == null ||
        previous.isLoading ||
        previous.query.scope == scope) {
      return;
    }
    final query = _queryFor(
      scope: scope,
      order: scope == UserBlogFeedScope.public
          ? (previous.query.order ?? UserBlogOrder.latest)
          : null,
    );
    await _replaceQuery(query, previous);
  }

  Future<void> selectOrder(UserBlogOrder order) async {
    final previous = state.value;
    if (previous == null ||
        previous.isLoading ||
        previous.query.scope != UserBlogFeedScope.public ||
        previous.query.order == order) {
      return;
    }
    await _replaceQuery(UserBlogDirectoryQuery.public(order: order), previous);
  }

  Future<void> loadNextPage() async {
    final previous = state.value;
    final pagination = previous?.data?.pagination;
    if (previous == null ||
        previous.isLoading ||
        pagination == null ||
        pagination.hasNext == false ||
        (pagination.totalPages != null &&
            pagination.currentPage >= pagination.totalPages!)) {
      return;
    }
    await _replaceQuery(
      UserBlogDirectoryQuery(
        scope: previous.query.scope,
        order: previous.query.order,
        page: pagination.currentPage + 1,
      ),
      previous,
    );
  }

  Future<void> _replaceQuery(
    UserBlogDirectoryQuery query,
    UserBlogDirectoryPageState previous,
  ) async {
    state = AsyncData(previous.copyWith(isLoading: true, clearFailure: true));
    state = AsyncData(
      await _load(
        query,
        previous: previous,
        cachePolicy: CacheLoadPolicy.cacheFirst,
      ),
    );
  }

  Future<UserBlogDirectoryPageState> _load(
    UserBlogDirectoryQuery query, {
    required UserBlogDirectoryPageState? previous,
    required CacheLoadPolicy cachePolicy,
  }) async {
    final result = await ref
        .read(userBlogDirectoryRepositoryProvider)
        .load(query, cachePolicy: cachePolicy);
    if (result case DataReadSuccess<
      UserBlogDirectoryData,
      UserBlogDirectoryReadCapabilities
    >(
      :final data,
      :final capabilities,
      :final metadata,
    )) {
      return UserBlogDirectoryPageState(
        query: query,
        data: data,
        capabilities: capabilities,
        metadata: metadata,
      );
    }
    return (previous ?? UserBlogDirectoryPageState(query: query)).copyWith(
      failure: result.failureOrNull,
      isLoading: false,
    );
  }

  UserBlogDirectoryQuery _queryFor({
    required UserBlogFeedScope scope,
    UserBlogOrder? order,
  }) {
    return scope == UserBlogFeedScope.public
        ? UserBlogDirectoryQuery.public(order: order ?? UserBlogOrder.latest)
        : scope == UserBlogFeedScope.self
        ? const UserBlogDirectoryQuery.self()
        : const UserBlogDirectoryQuery.friends();
  }
}

final class UserBlogDetailPageState {
  const UserBlogDetailPageState({
    this.data,
    this.capabilities,
    this.metadata,
    this.failure,
  });

  final UserBlogDetailData? data;
  final UserBlogDetailReadCapabilities? capabilities;
  final DataReadMetadata? metadata;
  final DataReadFailure<UserBlogDetailData, UserBlogDetailReadCapabilities>?
  failure;
}

final profileBlogDetailProvider = AsyncNotifierProvider.autoDispose
    .family<
      ProfileBlogDetailController,
      UserBlogDetailPageState,
      UserBlogDetailQuery
    >((query) => ProfileBlogDetailController(query));

final class ProfileBlogDetailController
    extends AsyncNotifier<UserBlogDetailPageState> {
  ProfileBlogDetailController(this._query);

  final UserBlogDetailQuery _query;

  @override
  Future<UserBlogDetailPageState> build() {
    return _load(previous: null, cachePolicy: CacheLoadPolicy.cacheFirst);
  }

  Future<void> refresh() async {
    final previous = state.value;
    state = AsyncData(
      await _load(
        previous: previous,
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<UserBlogDetailPageState> _load({
    required UserBlogDetailPageState? previous,
    required CacheLoadPolicy cachePolicy,
  }) async {
    final result = await ref
        .read(userBlogDetailRepositoryProvider)
        .load(_query, cachePolicy: cachePolicy);
    if (result case DataReadSuccess<
      UserBlogDetailData,
      UserBlogDetailReadCapabilities
    >(
      :final data,
      :final capabilities,
      :final metadata,
    )) {
      return UserBlogDetailPageState(
        data: data,
        capabilities: capabilities,
        metadata: metadata,
      );
    }
    return UserBlogDetailPageState(
      data: previous?.data,
      capabilities: previous?.capabilities,
      metadata: previous?.metadata,
      failure: result.failureOrNull,
    );
  }
}

class ProfileBlogPage extends ConsumerWidget {
  const ProfileBlogPage({
    super.key,
    this.initialScope = UserBlogFeedScope.public,
    this.initialOrder = UserBlogOrder.latest,
  });

  final UserBlogFeedScope initialScope;
  final UserBlogOrder initialOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = ProfileBlogPageArgs(
      initialScope: initialScope,
      initialOrder: initialOrder,
    );
    final asyncState = ref.watch(profileBlogListProvider(args));
    final state = asyncState.value;
    final data = state?.data;
    final controller = ref.read(profileBlogListProvider(args).notifier);
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(l10n.profileBlogTitle),
        actions: [
          IconButton(
            tooltip: l10n.profileBlogWrite,
            onPressed: () =>
                _showTodo(context, l10n.profileBlogWriteUnavailable),
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
      body: data != null
          ? RefreshIndicator(
              onRefresh: controller.refresh,
              child: _ProfileBlogListContent(
                data: data,
                capabilities: state?.capabilities,
                failure: state?.failure,
                palette: palette,
                imageHeaderBuilder: ref.watch(
                  imageRequestHeaderBuilderProvider,
                ),
                onSelectScope: controller.selectScope,
                onSelectOrder: controller.selectOrder,
                onOpenBlog: (item) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileBlogDetailPage(
                      ownerUserId: item.ownerUserId,
                      blogId: item.blogId,
                    ),
                  ),
                ),
                onLoadNextPage: _canLoadNext(data, state?.capabilities)
                    ? controller.loadNextPage
                    : null,
              ),
            )
          : asyncState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ProfileBlogError(
              error: state?.failure ?? asyncState.error,
              palette: palette,
              onRetry: controller.refresh,
            ),
    );
  }

  bool _canLoadNext(
    UserBlogDirectoryData data,
    UserBlogDirectoryReadCapabilities? capabilities,
  ) {
    final pagination = data.pagination;
    if (capabilities?.supports(
          UserBlogDirectoryCapability.directionalPagination,
        ) ==
        true) {
      return pagination.hasNext == true;
    }
    return capabilities?.supports(UserBlogDirectoryCapability.totalPageCount) ==
            true &&
        pagination.totalPages != null &&
        pagination.currentPage < pagination.totalPages!;
  }

  void _showTodo(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class ProfileBlogDetailPage extends ConsumerWidget {
  const ProfileBlogDetailPage({
    super.key,
    required this.ownerUserId,
    required this.blogId,
  });

  final String ownerUserId;
  final String blogId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = UserBlogDetailQuery(ownerUserId: ownerUserId, blogId: blogId);
    final asyncState = ref.watch(profileBlogDetailProvider(query));
    final state = asyncState.value;
    final data = state?.data;
    final palette = _ProfileBlogPalette.resolve(Theme.of(context));
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final l10n = AppLocalizations.of(context);
    final rawTitle = data?.title.trim();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(
          rawTitle?.isNotEmpty == true ? data!.title : l10n.profileBlogTitle,
        ),
      ),
      body: data != null
          ? RefreshIndicator(
              onRefresh: ref
                  .read(profileBlogDetailProvider(query).notifier)
                  .refresh,
              child: _ProfileBlogDetailContent(
                data: data,
                capabilities: state?.capabilities,
                failure: state?.failure,
                palette: palette,
                imageHeaderBuilder: imageHeaderBuilder,
              ),
            )
          : asyncState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ProfileBlogError(
              error: state?.failure ?? asyncState.error,
              palette: palette,
              onRetry: ref
                  .read(profileBlogDetailProvider(query).notifier)
                  .refresh,
            ),
    );
  }
}

class _ProfileBlogListContent extends StatelessWidget {
  const _ProfileBlogListContent({
    required this.data,
    required this.capabilities,
    required this.failure,
    required this.palette,
    required this.imageHeaderBuilder,
    required this.onSelectScope,
    required this.onSelectOrder,
    required this.onOpenBlog,
    required this.onLoadNextPage,
  });

  final UserBlogDirectoryData data;
  final UserBlogDirectoryReadCapabilities? capabilities;
  final Object? failure;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final ValueChanged<UserBlogFeedScope> onSelectScope;
  final ValueChanged<UserBlogOrder> onSelectOrder;
  final ValueChanged<UserBlogSummary> onOpenBlog;
  final VoidCallback? onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile-blog-list'),
      padding: EdgeInsets.zero,
      children: [
        if (failure != null)
          Padding(
            padding: const EdgeInsets.all(12),
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
        _ViewTabs(
          activeScope: data.scope,
          palette: palette,
          onSelect: onSelectScope,
        ),
        if (data.scope == UserBlogFeedScope.public)
          _OrderTabs(
            activeOrder: data.order ?? UserBlogOrder.latest,
            palette: palette,
            onSelect: onSelectOrder,
          ),
        if (data.items.isEmpty)
          _ProfileBlogEmptyState(
            message: AppLocalizations.of(context).profileBlogEmpty,
            palette: palette,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              children: [
                for (final item in data.items) ...[
                  _ProfileBlogListCard(
                    key: Key('profile-blog-item-${item.blogId}'),
                    item: item,
                    capabilities: capabilities,
                    palette: palette,
                    imageHeaderBuilder: imageHeaderBuilder,
                    onTap: () => onOpenBlog(item),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        if (data.pagination.totalPages != null ||
            data.pagination.hasPrevious != null ||
            data.pagination.hasNext != null)
          _PaginationBar(
            pagination: data.pagination,
            palette: palette,
            onLoadNextPage: onLoadNextPage,
          ),
      ],
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
    required this.imageHeaderBuilder,
    required this.onTap,
  });

  final UserBlogSummary item;
  final UserBlogDirectoryReadCapabilities? capabilities;
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
                  if (capabilities?.supports(
                        UserBlogDirectoryCapability.avatarReference,
                      ) ==
                      true)
                    _ProfileBlogAvatar(
                      imageUrl: item.avatarUrl,
                      ownerId: item.ownerUserId,
                      radius: 17,
                      imageHeaderBuilder: imageHeaderBuilder,
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
                          Text(
                            item.authorName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: palette.title,
                                  fontWeight: FontWeight.w800,
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
    required this.imageHeaderBuilder,
  });

  final UserBlogDetailData data;
  final UserBlogDetailReadCapabilities? capabilities;
  final Object? failure;
  final _ProfileBlogPalette palette;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile-blog-detail'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
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
          imageHeaderBuilder: imageHeaderBuilder,
        ),
        if (capabilities?.supports(UserBlogDetailCapability.orderedComments) ==
                true &&
            data.comments.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context).profileBlogComments,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final comment in data.comments) ...[
            _CommentCard(
              key: Key('profile-blog-comment-${comment.commentId}'),
              comment: comment,
              capabilities: capabilities,
              palette: palette,
              imageHeaderBuilder: imageHeaderBuilder,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (capabilities?.supports(
                  UserBlogDetailCapability.commentingAvailability,
                ) ==
                true &&
            data.commentsOpen == true) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('profile-blog-comment-placeholder'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).profileBlogCommentUnavailable,
                ),
              ),
            ),
            icon: const Icon(Icons.comment_outlined),
            label: Text(AppLocalizations.of(context).profileBlogComment),
          ),
        ],
      ],
    );
  }
}

class _BlogDetailCard extends StatelessWidget {
  const _BlogDetailCard({
    required this.data,
    required this.capabilities,
    required this.palette,
    required this.imageHeaderBuilder,
  });

  final UserBlogDetailData data;
  final UserBlogDetailReadCapabilities? capabilities;
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
              if (capabilities?.supports(
                    UserBlogDetailCapability.avatarReference,
                  ) ==
                  true) ...[
                _ProfileBlogAvatar(
                  imageUrl: data.avatarUrl,
                  ownerId: data.ownerUserId,
                  radius: 17,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  _detailMeta(context, data),
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
              html: data.bodyHtml,
              sourceId: 'profile-blog-${data.blogId}',
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: data.blogId,
              contentImageKind: ForumImageKind.blogInline,
              surfaceColor: palette.card,
              foregroundColor: palette.body,
              onOpenLink: (url) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(url))),
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
    required this.imageHeaderBuilder,
  });

  final UserBlogComment comment;
  final UserBlogDetailReadCapabilities? capabilities;
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
              if (capabilities?.supports(
                    UserBlogDetailCapability.commentAvatarReference,
                  ) ==
                  true) ...[
                _ProfileBlogAvatar(
                  imageUrl: comment.avatarUrl,
                  ownerId: comment.authorUserId ?? comment.authorName,
                  radius: 15,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
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
              imageHeaderBuilder: imageHeaderBuilder,
              imageCacheOwnerId: comment.commentId,
              contentImageKind: ForumImageKind.blogInline,
              surfaceColor: palette.card,
              foregroundColor: palette.body,
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
    required this.imageHeaderBuilder,
  });

  final String? imageUrl;
  final String ownerId;
  final double radius;
  final ImageRequestHeaderBuilder imageHeaderBuilder;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = imageUrl?.trim();
    return ForumCachedAvatar(
      imageUrl: url,
      ownerId: ownerId.trim().isEmpty ? (url ?? 'unknown') : ownerId,
      ownerType: ImageCacheOwnerType.profile,
      size: size,
      headerBuilder: imageHeaderBuilder,
    );
  }
}

class _ProfileBlogError extends StatelessWidget {
  const _ProfileBlogError({
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final Object? error;
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
              AppLocalizations.of(context).profileBlogLoadFailed(
                LocalizedErrorSummary.resolve(
                  AppLocalizations.of(context),
                  error,
                ),
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.body),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
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
