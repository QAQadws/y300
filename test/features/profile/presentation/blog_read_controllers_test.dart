import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';

void main() {
  ProfileBlogPageController feed(
    _Directory repository, {
    ProfileBlogPageArgs args = const ProfileBlogPageArgs(),
    String? account = '101',
  }) {
    final controller = ProfileBlogPageController(
      repository: repository,
      accountId: account,
      args: args,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  ProfileBlogDetailController detail(
    _Details repository, {
    UserBlogDetailQuery query = const UserBlogDetailQuery(
      ownerUserId: '101',
      blogId: '11',
    ),
  }) {
    final controller = ProfileBlogDetailController(
      repository: repository,
      query: query,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test(
    'hidden feeds are lazy and active duplicate reads share one request',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      await controller.setActive(false);
      expect(repository.requests, isEmpty);
      final first = controller.setActive(true);
      expect(controller.value.isLoading, isTrue);
      expect(controller.setActive(true), same(first));
      expect(controller.refresh(), same(first));
      repository.succeed(0);
      await first;
      await controller.setActive(false);
      await controller.setActive(true);
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'switching tabs cancels slow work and ignores its late response',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      final first = controller.setActive(true);
      final friends = controller.selectScope(UserBlogFeedScope.friends);
      expect(repository.requests[0].cancellation.isCancelled, isTrue);
      expect(controller.value.query.scope, UserBlogFeedScope.friends);
      repository.succeed(1, ids: ['22']);
      await friends;
      repository.succeed(0, ids: ['11']);
      await first;
      expect(controller.value.data!.items.single.blogId, '22');
      expect(controller.value.query.scope, UserBlogFeedScope.friends);
    },
  );

  test(
    'each tab retains its last filter and content without prefetching others',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.selectOrder(UserBlogOrder.recommended);
      repository.succeed(1, ids: ['12']);
      await pending;
      pending = controller.selectCategory('8');
      repository.succeed(2, ids: ['13']);
      await pending;
      pending = controller.selectScope(UserBlogFeedScope.self);
      expect(repository.requests.last.query.ownerUserId, '101');
      repository.succeed(3, ids: ['14']);
      await pending;
      await controller.selectScope(UserBlogFeedScope.public);
      expect(repository.requests, hasLength(4));
      expect(controller.value.query.order, UserBlogOrder.recommended);
      expect(controller.value.query.categoryId, '8');
      expect(controller.value.data!.items.single.blogId, '13');
    },
  );

  test(
    'next pages preserve filter identities, append and deduplicate entries',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.selectCategory('8');
      repository.succeed(1, ids: ['11', '12']);
      await pending;
      pending = controller.loadNextPage();
      await controller.loadNextPage();
      expect(repository.requests, hasLength(3));
      expect(
        repository.requests.last.query,
        const UserBlogDirectoryQuery.public(page: 2, categoryId: '8'),
      );
      repository.succeed(2, ids: ['12', '13'], next: false);
      await pending;
      expect(controller.value.data!.items.map((e) => e.blogId), [
        '11',
        '12',
        '13',
      ]);
      await controller.loadNextPage();
      expect(repository.requests, hasLength(3));
    },
  );

  test(
    'a personal category stays scoped to its author on later pages',
    () async {
      final repository = _Directory();
      final controller = feed(
        repository,
        args: const ProfileBlogPageArgs(ownerUserId: '102'),
      );
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.selectCategory('7');
      repository.succeed(1);
      await pending;
      await controller.selectScope(UserBlogFeedScope.public);
      expect(repository.requests, hasLength(2));
      pending = controller.loadNextPage();
      expect(
        repository.requests.last.query,
        const UserBlogDirectoryQuery.self(
          ownerUserId: '102',
          personalCategoryId: '7',
          page: 2,
        ),
      );
      repository.succeed(2, next: false);
      await pending;
    },
  );

  test(
    'anonymous readers can open public authors but not their own or friends feed',
    () async {
      final repository = _Directory();
      final controller = feed(
        repository,
        account: null,
        args: const ProfileBlogPageArgs(initialScope: UserBlogFeedScope.self),
      );
      await controller.setActive(true);
      expect(controller.value.failure!.kind, DataReadFailureKind.unauthorized);
      await controller.selectScope(UserBlogFeedScope.friends);
      expect(repository.requests, isEmpty);
      final author = feed(
        repository,
        account: null,
        args: const ProfileBlogPageArgs(ownerUserId: '102'),
      );
      final pending = author.setActive(true);
      repository.succeed(0);
      await pending;
      expect(author.value.data, isNotNull);
    },
  );

  test('failed paging retains entries and retries the same page', () async {
    final repository = _Directory();
    final controller = feed(repository);
    var pending = controller.setActive(true);
    repository.succeed(0);
    await pending;
    pending = controller.loadNextPage();
    repository.requests[1].result.complete(
      const DataReadFailure(
        diagnosticMessage: 'fixture_failure',
        kind: DataReadFailureKind.network,
      ),
    );
    await pending;
    expect(controller.value.query.page, 1);
    expect(controller.value.data!.items.single.blogId, '11');
    pending = controller.loadNextPage();
    expect(repository.requests[2].query.page, 2);
    repository.succeed(2, ids: ['12'], next: false);
    await pending;
    expect(controller.value.failure, isNull);
    expect(controller.value.data!.items.map((e) => e.blogId), ['11', '12']);
  });

  test(
    'refresh starts from page one and keeps content during a network failure',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.loadNextPage();
      repository.succeed(1, ids: ['12'], next: false);
      await pending;
      pending = controller.refresh();
      expect(repository.requests[2].query.page, 1);
      expect(repository.requests[2].policy, CacheLoadPolicy.networkFirst);
      repository.requests[2].result.complete(
        const DataReadFailure(
          diagnosticMessage: 'fixture_failure',
          kind: DataReadFailureKind.network,
        ),
      );
      await pending;
      expect(controller.value.data!.items, hasLength(2));
    },
  );

  test(
    'refresh supersedes a pending next page without accepting its late append',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      final first = controller.setActive(true);
      repository.succeed(0);
      await first;
      final next = controller.loadNextPage();
      final refresh = controller.refresh();
      expect(repository.requests[1].cancellation.isCancelled, isTrue);
      expect(repository.requests[2].query.page, 1);
      repository.succeed(2, ids: ['20']);
      await refresh;
      repository.succeed(1, ids: ['12']);
      await next;
      expect(controller.value.data!.items.single.blogId, '20');
    },
  );

  test('an expired account drops retained private tabs too', () async {
    final repository = _Directory();
    final controller = feed(
      repository,
      args: const ProfileBlogPageArgs(initialScope: UserBlogFeedScope.self),
    );
    var pending = controller.setActive(true);
    repository.succeed(0);
    await pending;
    pending = controller.selectScope(UserBlogFeedScope.friends);
    repository.requests[1].result.complete(
      const DataReadFailure(
        diagnosticMessage: 'fixture_failure',
        kind: DataReadFailureKind.unauthorized,
      ),
    );
    await pending;
    pending = controller.selectScope(UserBlogFeedScope.self);
    expect(controller.value.data, isNull);
    expect(repository.requests, hasLength(3));
    repository.requests[2].result.complete(
      const DataReadFailure(
        diagnosticMessage: 'fixture_failure',
        kind: DataReadFailureKind.unauthorized,
      ),
    );
    await pending;
  });

  test(
    'hiding a pending route cancels it and reactivation starts a new read',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      final old = controller.setActive(true);
      await controller.setActive(false);
      expect(repository.requests[0].cancellation.isCancelled, isTrue);
      final fresh = controller.setActive(true);
      repository.succeed(1, ids: ['12']);
      await fresh;
      repository.succeed(0, ids: ['11']);
      await old;
      expect(controller.value.data!.items.single.blogId, '12');
    },
  );

  test(
    'disposal cancels work even if a repository returns after cancellation',
    () async {
      final repository = _Directory();
      final controller = ProfileBlogPageController(
        repository: repository,
        accountId: '101',
        args: const ProfileBlogPageArgs(),
      );
      final pending = controller.setActive(true);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.dispose();
      expect(repository.requests[0].cancellation.isCancelled, isTrue);
      repository.succeed(0);
      await pending;
      expect(notifications, 0);
    },
  );

  test(
    'thrown repository failures become safe structured state and can retry',
    () async {
      final repository = _Directory();
      final controller = feed(repository);
      final pending = controller.setActive(true);
      repository.requests[0].result.completeError(
        StateError('private response'),
      );
      await pending;
      expect(
        controller.value.failure!.diagnosticMessage,
        isNot(contains('private')),
      );
      final retry = controller.refresh();
      repository.succeed(1);
      await retry;
      expect(controller.value.failure, isNull);
    },
  );

  test(
    'account changes replace feed and detail controllers and cancel old reads',
    () async {
      final directory = _Directory();
      final details = _Details();
      final container = ProviderContainer(
        overrides: [
          blogAccountIdProvider.overrideWithValue('101'),
          userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
          userBlogDetailRepositoryProvider.overrideWithValue(details),
        ],
      );
      addTearDown(container.dispose);
      final feedProvider = profileBlogListProvider(
        const ProfileBlogPageArgs(initialScope: UserBlogFeedScope.self),
      );
      final detailProvider = profileBlogDetailProvider((
        const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'),
        Object(),
      ));
      container.listen(feedProvider, (_, _) {});
      container.listen(detailProvider, (_, _) {});
      final oldFeed = container.read(feedProvider);
      final oldDetail = container.read(detailProvider);
      final firstFeed = oldFeed.setActive(true);
      final firstDetail = oldDetail.setActive(true);
      container.updateOverrides([
        blogAccountIdProvider.overrideWithValue('102'),
        userBlogDirectoryRepositoryProvider.overrideWithValue(directory),
        userBlogDetailRepositoryProvider.overrideWithValue(details),
      ]);
      await container.pump();
      expect(directory.requests[0].cancellation.isCancelled, isTrue);
      expect(details.requests[0].cancellation.isCancelled, isTrue);
      final nextFeed = container.read(feedProvider);
      final nextDetail = container.read(detailProvider);
      expect(nextFeed, isNot(same(oldFeed)));
      expect(nextDetail, isNot(same(oldDetail)));
      directory.succeed(0);
      details.succeed(0);
      await Future.wait([firstFeed, firstDetail]);
      expect(nextFeed.value.data, isNull);
      expect(nextDetail.value.data, isNull);
      expect(nextFeed.value.query.ownerUserId, '102');
    },
  );

  test(
    'comment pagination appends without replacing the displayed article',
    () async {
      final repository = _Details();
      final controller = detail(repository);
      var pending = controller.setActive(true);
      repository.succeed(0, ids: ['5', '6']);
      await pending;
      final body = controller.value.data!.bodyHtml;
      pending = controller.loadNextComments();
      expect(controller.value.data!.bodyHtml, body);
      repository.succeed(
        1,
        ids: ['6', '7'],
        body: '<p>Concurrent edit</p>',
        next: false,
      );
      await pending;
      expect(controller.value.data!.bodyHtml, body);
      expect(controller.value.data!.comments.map((c) => c.commentId), [
        '5',
        '6',
        '7',
      ]);
      expect(controller.value.firstCommentPage, 1);
      expect(controller.value.canLoadNext, isFalse);
    },
  );

  test(
    'a single comment link is kept separate from the whole comment list',
    () async {
      final repository = _Details();
      final controller = detail(
        repository,
        query: const UserBlogDetailQuery(
          ownerUserId: '101',
          blogId: '11',
          commentId: '6',
        ),
      );
      var pending = controller.setActive(true);
      repository.succeed(0, ids: ['6']);
      await pending;
      await controller.loadNextComments();
      expect(repository.requests, hasLength(1));
      pending = controller.selectCommentPage(1);
      expect(repository.requests.last.query.commentId, isNull);
      repository.succeed(1, ids: ['5', '6']);
      await pending;
      expect(controller.value.query.commentId, isNull);
    },
  );

  test(
    'last page uses the source cursor and earlier links replace comments',
    () async {
      final repository = _Details();
      final controller = detail(repository);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.loadLastComments();
      expect(repository.requests.last.query.lastCommentPage, isTrue);
      repository.succeed(1, page: 9, ids: ['90'], next: false);
      await pending;
      expect(controller.value.firstCommentPage, 9);
      pending = controller.selectCommentPage(8);
      repository.succeed(2, ids: ['80']);
      await pending;
      expect(controller.value.data!.comments.single.commentId, '80');
      expect(controller.value.firstCommentPage, 8);
    },
  );

  test(
    'a private or deleted article cannot retain old body after refresh',
    () async {
      final repository = _Details();
      final controller = detail(repository);
      var pending = controller.setActive(true);
      repository.succeed(0);
      await pending;
      pending = controller.refresh();
      repository.requests[1].result.complete(
        const DataReadFailure(
          diagnosticMessage: 'fixture_failure',
          kind: DataReadFailureKind.business,
          code: 'user_blog_private',
        ),
      );
      await pending;
      expect(controller.value.data, isNull);
      expect(controller.value.failure!.code, 'user_blog_private');
    },
  );
}

class _Pending<Q, R> {
  _Pending(this.query, this.cancellation, this.policy);
  final Q query;
  final ForumRequestCancellation cancellation;
  final CacheLoadPolicy policy;
  final result = Completer<R>();
}

class _Directory implements UserBlogDirectoryRepository {
  final requests = <_Pending<UserBlogDirectoryQuery, BlogDirectoryRead>>[];
  @override
  UserBlogDirectorySourceCapabilities get capabilities =>
      UserBlogDirectorySourceCapabilities(
        values: DataCapabilitySet.supported(UserBlogDirectoryCapability.values),
        paginationPrecision: PaginationPrecision.exact,
      );
  @override
  Future<BlogDirectoryRead> load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final request = _Pending<UserBlogDirectoryQuery, BlogDirectoryRead>(
      query,
      cancellation!,
      cachePolicy,
    );
    requests.add(request);
    return request.result.future;
  }

  void succeed(int index, {List<String> ids = const ['11'], bool next = true}) {
    final request = requests[index];
    request.result.complete(
      DataReadSuccess(
        data: UserBlogDirectoryData(
          scope: request.query.scope,
          order: request.query.order,
          items: [
            for (final id in ids)
              UserBlogSummary(
                blogId: id,
                ownerUserId: '101',
                title: 'Entry $id',
              ),
          ],
          categories: const [UserBlogCategory(id: '8', name: 'Stories')],
          pagination: UserBlogPagination(
            currentPage: request.query.page,
            hasNext: next,
          ),
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }
}

class _Details implements UserBlogDetailRepository {
  final requests = <_Pending<UserBlogDetailQuery, BlogDetailRead>>[];
  @override
  UserBlogDetailSourceCapabilities get capabilities =>
      UserBlogDetailSourceCapabilities(
        values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
      );
  @override
  Future<BlogDetailRead> load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final request = _Pending<UserBlogDetailQuery, BlogDetailRead>(
      query,
      cancellation!,
      cachePolicy,
    );
    requests.add(request);
    return request.result.future;
  }

  void succeed(
    int index, {
    List<String> ids = const ['5'],
    String body = '<p>Article</p>',
    bool next = true,
    int? page,
  }) {
    final request = requests[index];
    request.result.complete(
      DataReadSuccess(
        data: UserBlogDetailData(
          ownerUserId: request.query.ownerUserId,
          blogId: request.query.blogId,
          title: 'Title',
          bodyHtml: body,
          comments: [
            for (final id in ids)
              UserBlogComment(
                commentId: id,
                authorName: 'Reader',
                bodyHtml: '<p>Comment $id</p>',
              ),
          ],
          commentPagination: UserBlogPagination(
            currentPage: page ?? request.query.page,
            hasNext: next,
          ),
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }
}
