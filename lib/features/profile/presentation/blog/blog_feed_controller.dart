import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef BlogDirectoryRead =
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>;

@immutable
final class ProfileBlogPageArgs {
  const ProfileBlogPageArgs({
    this.initialScope = UserBlogFeedScope.public,
    this.initialOrder = UserBlogOrder.latest,
    this.ownerUserId,
    this.routeOwner,
  });

  final UserBlogFeedScope initialScope;
  final UserBlogOrder initialOrder;
  final String? ownerUserId;
  final Object? routeOwner;

  @override
  bool operator ==(Object other) =>
      other is ProfileBlogPageArgs &&
      initialScope == other.initialScope &&
      initialOrder == other.initialOrder &&
      ownerUserId == other.ownerUserId &&
      routeOwner == other.routeOwner;
  @override
  int get hashCode =>
      Object.hash(initialScope, initialOrder, ownerUserId, routeOwner);
}

@immutable
final class UserBlogDirectoryPageState {
  const UserBlogDirectoryPageState({
    required this.query,
    this.data,
    this.capabilities,
    this.failure,
    this.isLoading = false,
    this.categories = const [],
  });

  final UserBlogDirectoryQuery query;
  final UserBlogDirectoryData? data;
  final UserBlogDirectoryReadCapabilities? capabilities;
  final DataReadFailure<
    UserBlogDirectoryData,
    UserBlogDirectoryReadCapabilities
  >?
  failure;
  final bool isLoading;
  final List<UserBlogCategory> categories;

  bool get canLoadNext =>
      !isLoading &&
      data != null &&
      ((capabilities?.supports(
                    UserBlogDirectoryCapability.directionalPagination,
                  ) ==
                  true &&
              data!.pagination.hasNext == true) ||
          (capabilities?.supports(UserBlogDirectoryCapability.totalPageCount) ==
                  true &&
              data!.pagination.hasNext != false &&
              data!.pagination.totalPages != null &&
              data!.pagination.currentPage < data!.pagination.totalPages!));

  UserBlogDirectoryPageState waiting({bool loading = true}) =>
      UserBlogDirectoryPageState(
        query: query,
        data: data,
        capabilities: capabilities,
        isLoading: loading,
        categories: categories,
      );
}

/// Retains the last selection for each tab for this route and account only.
/// Requests are lazy; switching tabs cancels old work without locking the UI.
final class ProfileBlogPageController
    extends ValueNotifier<UserBlogDirectoryPageState> {
  ProfileBlogPageController({
    required UserBlogDirectoryRepository repository,
    required this.accountId,
    required ProfileBlogPageArgs args,
  }) : _repository = repository,
       _args = args,
       super(UserBlogDirectoryPageState(query: _initialQuery(args, accountId)));

  final UserBlogDirectoryRepository _repository;
  final String? accountId;
  final ProfileBlogPageArgs _args;
  final _retained = <UserBlogFeedScope, UserBlogDirectoryPageState>{};
  ForumRequestCancellation? _cancellation;
  Future<void>? _pending;
  bool _active = false;
  bool _disposed = false;
  bool _refreshing = false;
  int _generation = 0;

  Future<void> setActive(bool active) {
    if (_disposed) return Future.value();
    _active = active;
    if (!active) {
      _cancel();
      if (value.isLoading) value = value.waiting(loading: false);
      return Future.value();
    }
    if (_pending != null) return _pending!;
    return value.data == null && value.failure == null
        ? _load(value.query)
        : Future.value();
  }

  Future<void> refresh() {
    if (_disposed || !_active) return Future.value();
    if (value.isLoading) {
      if (_refreshing || value.data == null) return _pending ?? Future.value();
      _cancel();
    }
    return _load(_page(value.query, 1), refresh: true);
  }

  Future<void> selectScope(UserBlogFeedScope scope) {
    if (_disposed || _args.ownerUserId != null || value.query.scope == scope) {
      return Future.value();
    }
    _cancel();
    _retained[value.query.scope] = value.waiting(loading: false);
    value =
        _retained[scope] ??
        UserBlogDirectoryPageState(
          query: _initialQuery(
            ProfileBlogPageArgs(
              initialScope: scope,
              initialOrder: _args.initialOrder,
            ),
            accountId,
          ),
        );
    return setActive(_active);
  }

  Future<void> selectOrder(UserBlogOrder order) {
    final query = value.query;
    if (query.scope != UserBlogFeedScope.public || query.order == order) {
      return Future.value();
    }
    return _select(
      UserBlogDirectoryQuery.public(order: order, categoryId: query.categoryId),
    );
  }

  Future<void> selectCategory(String? id) {
    final query = value.query;
    final normalized = id == '0' ? null : id;
    if (query.scope == UserBlogFeedScope.friends ||
        (query.scope == UserBlogFeedScope.public
                ? query.categoryId
                : query.personalCategoryId) ==
            normalized) {
      return Future.value();
    }
    return _select(
      UserBlogDirectoryQuery(
        scope: query.scope,
        order: query.order,
        ownerUserId: query.ownerUserId,
        categoryId: query.scope == UserBlogFeedScope.public ? normalized : null,
        personalCategoryId: query.scope == UserBlogFeedScope.self
            ? normalized
            : null,
      ),
    );
  }

  Future<void> _select(UserBlogDirectoryQuery query) {
    if (_disposed) return Future.value();
    _cancel();
    value = UserBlogDirectoryPageState(
      query: query,
      categories: value.categories,
    );
    return setActive(_active);
  }

  Future<void> loadNextPage() => !_active || _disposed || !value.canLoadNext
      ? Future.value()
      : _load(
          _page(value.query, value.data!.pagination.currentPage + 1),
          append: true,
        );

  Future<void> _load(
    UserBlogDirectoryQuery query, {
    bool refresh = false,
    bool append = false,
  }) {
    final previous = value;
    final generation = ++_generation;
    final cancellation = ForumRequestCancellation();
    _cancellation = cancellation;
    _refreshing = refresh;
    value = previous.waiting();
    return _pending = _perform(query, cancellation, refresh: refresh).then((
      result,
    ) {
      if (_disposed || generation != _generation || cancellation.isCancelled) {
        return;
      }
      _pending = null;
      _cancellation = null;
      if (result case DataReadSuccess(:final data, :final capabilities)) {
        value = UserBlogDirectoryPageState(
          query: query,
          data: append && previous.data != null
              ? _append(previous.data!, data)
              : data,
          capabilities: capabilities,
          categories: data.categories,
        );
      } else {
        final failure = result.failureOrNull!;
        if (failure.kind == DataReadFailureKind.unauthorized) _retained.clear();
        // A denied or vanished private feed must not remain readable from a
        // previous successful response. Transport failures can retain content.
        final retain = !{
          DataReadFailureKind.unauthorized,
          DataReadFailureKind.business,
        }.contains(failure.kind);
        value = UserBlogDirectoryPageState(
          query: previous.query,
          data: retain ? previous.data : null,
          capabilities: retain ? previous.capabilities : null,
          failure: failure,
          categories: retain ? previous.categories : const [],
        );
      }
    });
  }

  Future<BlogDirectoryRead> _perform(
    UserBlogDirectoryQuery request,
    ForumRequestCancellation token, {
    required bool refresh,
  }) async {
    if (accountId == null &&
        (request.scope == UserBlogFeedScope.friends ||
            (request.scope == UserBlogFeedScope.self &&
                request.ownerUserId == null))) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_blog_login_required',
        diagnosticMessage: 'user_blog_login_required',
      );
    }
    try {
      return await _repository.load(
        request,
        cachePolicy: refresh
            ? CacheLoadPolicy.networkFirst
            : CacheLoadPolicy.cacheFirst,
        cancellation: token,
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        code: 'blog_read_failed',
        diagnosticMessage: 'blog_read_failed',
      );
    }
  }

  void _cancel() {
    ++_generation;
    _cancellation?.cancel();
    _cancellation = null;
    _pending = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    _retained.clear();
    super.dispose();
  }
}

UserBlogDirectoryQuery _initialQuery(
  ProfileBlogPageArgs args,
  String? account,
) => args.ownerUserId != null || args.initialScope == UserBlogFeedScope.self
    ? UserBlogDirectoryQuery.self(ownerUserId: args.ownerUserId ?? account)
    : args.initialScope == UserBlogFeedScope.friends
    ? const UserBlogDirectoryQuery.friends()
    : UserBlogDirectoryQuery.public(order: args.initialOrder);

UserBlogDirectoryQuery _page(UserBlogDirectoryQuery query, int page) =>
    UserBlogDirectoryQuery(
      scope: query.scope,
      order: query.order,
      page: page,
      ownerUserId: query.ownerUserId,
      categoryId: query.categoryId,
      personalCategoryId: query.personalCategoryId,
    );

UserBlogDirectoryData _append(
  UserBlogDirectoryData previous,
  UserBlogDirectoryData next,
) => UserBlogDirectoryData(
  scope: next.scope,
  order: next.order,
  items: List.unmodifiable(
    {
      for (final item in [...previous.items, ...next.items])
        (item.ownerUserId, item.blogId): item,
    }.values,
  ),
  pagination: next.pagination,
  categories: next.categories,
);
