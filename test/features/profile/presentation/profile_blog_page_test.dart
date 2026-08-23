import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('ProfileBlogPage switches structured queries and opens detail', (
    tester,
  ) async {
    final directoryRepository = _FakeBlogDirectoryRepository();
    final detailRepository = _FakeBlogDetailRepository();
    await _pumpBlogPage(
      tester,
      directoryRepository: directoryRepository,
      detailRepository: detailRepository,
    );

    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
    expect(find.byKey(const Key('profile-blog-view-tabs')), findsOneWidget);
    expect(find.text('随便看看'), findsOneWidget);
    expect(find.text('最新发表的日志'), findsOneWidget);
    expect(find.text('一种体验'), findsOneWidget);

    await tester.tap(find.text('推荐阅读的日志'));
    await tester.pumpAndSettle();

    expect(directoryRepository.queries.last.order, UserBlogOrder.recommended);
    expect(find.text('我们小区的公共交通极其不便利'), findsOneWidget);

    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();

    expect(directoryRepository.queries.last.scope, UserBlogFeedScope.self);
    expect(directoryRepository.queries.last.order, isNull);
    expect(find.text('还没有相关的日志'), findsOneWidget);

    await tester.tap(find.text('随便看看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推荐阅读的日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我们小区的公共交通极其不便利'));
    await tester.pumpAndSettle();

    expect(detailRepository.queries.single.ownerUserId, '257582');
    expect(detailRepository.queries.single.blogId, '117548');
    expect(find.byKey(const Key('profile-blog-detail')), findsOneWidget);
    expect(
      find.text('hsyhlj · 2026-6-18 00:25 · 浏览 39 · 评论 1'),
      findsOneWidget,
    );
    expect(_richTextContaining('一直对着电脑屏幕'), findsOneWidget);
    expect(find.text('日志评论'), findsOneWidget);
    expect(_richTextContaining('探险的感觉'), findsOneWidget);
  });

  testWidgets('next page constructs a page-only domain query', (tester) async {
    final repository = _FakeBlogDirectoryRepository();
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
    );

    await tester.tap(find.byKey(const Key('profile-blog-next-page-button')));
    await tester.pumpAndSettle();

    expect(repository.queries.last.page, 2);
    expect(repository.queries.last.scope, UserBlogFeedScope.public);
    expect(repository.queries.last.order, UserBlogOrder.latest);
    expect(find.text('第二页日志'), findsOneWidget);
  });

  testWidgets('capabilities hide optional list and detail fields', (
    tester,
  ) async {
    final directoryCapabilities = _directoryCapabilities(
      supported: const <UserBlogDirectoryCapability>[
        UserBlogDirectoryCapability.stableFeedIdentity,
        UserBlogDirectoryCapability.orderedEntries,
        UserBlogDirectoryCapability.stableBlogIdentity,
        UserBlogDirectoryCapability.stableOwnerIdentity,
        UserBlogDirectoryCapability.title,
      ],
    );
    final detailCapabilities = _detailCapabilities(
      supported: const <UserBlogDetailCapability>[
        UserBlogDetailCapability.stableBlogIdentity,
        UserBlogDetailCapability.stableOwnerIdentity,
        UserBlogDetailCapability.title,
        UserBlogDetailCapability.bodyMarkup,
      ],
    );
    await _pumpBlogPage(
      tester,
      directoryRepository: _FakeBlogDirectoryRepository(
        capabilities: directoryCapabilities,
      ),
      detailRepository: _FakeBlogDetailRepository(
        capabilities: detailCapabilities,
      ),
    );

    expect(find.text('一种体验'), findsOneWidget);
    expect(find.text('抉择'), findsNothing);
    expect(find.text('2026-6-21 13:06'), findsNothing);
    expect(find.textContaining('作为女生'), findsNothing);

    await tester.tap(find.text('一种体验'));
    await tester.pumpAndSettle();

    expect(find.textContaining('浏览 39'), findsNothing);
    expect(find.text('日志评论'), findsNothing);
    expect(
      find.byKey(const Key('profile-blog-comment-placeholder')),
      findsNothing,
    );
  });

  testWidgets('refresh failure retains existing directory content', (
    tester,
  ) async {
    final repository = _FakeBlogDirectoryRepository(failAfterSuccess: true);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileBlogPage)),
    );

    await container
        .read(profileBlogListProvider(const ProfileBlogPageArgs()).notifier)
        .refresh();
    await tester.pumpAndSettle();

    expect(find.text('一种体验'), findsOneWidget);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(repository.policies, <CacheLoadPolicy>[
      CacheLoadPolicy.cacheFirst,
      CacheLoadPolicy.networkFirst,
    ]);
  });

  testWidgets('initial failure shows retry and then loads content', (
    tester,
  ) async {
    final repository = _FakeBlogDirectoryRepository(failFirst: true);
    await _pumpBlogPage(
      tester,
      directoryRepository: repository,
      detailRepository: _FakeBlogDetailRepository(),
      settle: false,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('一种体验'), findsOneWidget);
  });

  testWidgets('ProfileBlogPage localizes chrome and preserves server titles', (
    tester,
  ) async {
    await _pumpBlogPage(
      tester,
      directoryRepository: _FakeBlogDirectoryRepository(),
      detailRepository: _FakeBlogDetailRepository(),
      locale: const Locale('zh', 'TW'),
    );

    expect(find.text('隨便看看'), findsOneWidget);
    expect(find.text('最新發表的日誌'), findsOneWidget);
    expect(find.text('一种体验'), findsOneWidget);
  });

  testWidgets('blog layout remains usable at 300dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userBlogDirectoryRepositoryProvider.overrideWithValue(
            _FakeBlogDirectoryRepository(),
          ),
          userBlogDetailRepositoryProvider.overrideWithValue(
            _FakeBlogDetailRepository(),
          ),
          imageRequestHeaderBuilderProvider.overrideWithValue(
            const _StaticImageHeaderBuilder(),
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const LocalizedTestApp(home: ProfileBlogPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
  });
}

Future<void> _pumpBlogPage(
  WidgetTester tester, {
  required UserBlogDirectoryRepository directoryRepository,
  required UserBlogDetailRepository detailRepository,
  Locale locale = const Locale('zh'),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userBlogDirectoryRepositoryProvider.overrideWithValue(
          directoryRepository,
        ),
        userBlogDetailRepositoryProvider.overrideWithValue(detailRepository),
        imageRequestHeaderBuilderProvider.overrideWithValue(
          const _StaticImageHeaderBuilder(),
        ),
      ],
      child: LocalizedTestApp(locale: locale, home: const ProfileBlogPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

UserBlogDirectoryReadCapabilities _directoryCapabilities({
  Iterable<UserBlogDirectoryCapability> supported =
      UserBlogDirectoryCapability.values,
}) {
  return UserBlogDirectoryReadCapabilities(
    values: DataCapabilitySet<UserBlogDirectoryCapability>.from(
      supported: supported,
      unsupported: UserBlogDirectoryCapability.values.where(
        (value) => !supported.contains(value),
      ),
    ),
    paginationPrecision:
        supported.contains(UserBlogDirectoryCapability.totalPageCount)
        ? PaginationPrecision.exact
        : PaginationPrecision.unknown,
  );
}

UserBlogDetailReadCapabilities _detailCapabilities({
  Iterable<UserBlogDetailCapability> supported =
      UserBlogDetailCapability.values,
}) {
  return UserBlogDetailReadCapabilities(
    values: DataCapabilitySet<UserBlogDetailCapability>.from(
      supported: supported,
      unsupported: UserBlogDetailCapability.values.where(
        (value) => !supported.contains(value),
      ),
    ),
  );
}

class _FakeBlogDirectoryRepository implements UserBlogDirectoryRepository {
  _FakeBlogDirectoryRepository({
    UserBlogDirectoryReadCapabilities? capabilities,
    this.failAfterSuccess = false,
    this.failFirst = false,
  }) : readCapabilities = capabilities ?? _directoryCapabilities();

  final UserBlogDirectoryReadCapabilities readCapabilities;
  final bool failAfterSuccess;
  final bool failFirst;
  final List<UserBlogDirectoryQuery> queries = <UserBlogDirectoryQuery>[];
  final List<CacheLoadPolicy> policies = <CacheLoadPolicy>[];

  @override
  UserBlogDirectorySourceCapabilities get capabilities =>
      UserBlogDirectorySourceCapabilities(
        values: readCapabilities.values,
        paginationPrecision: readCapabilities.paginationPrecision,
      );

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    if ((failFirst && queries.length == 1) ||
        (failAfterSuccess && queries.length > 1)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        diagnosticMessage: 'network failure',
      );
    }
    return DataReadSuccess(
      data: _directoryData(query),
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  UserBlogDirectoryData _directoryData(UserBlogDirectoryQuery query) {
    if (query.scope != UserBlogFeedScope.public) {
      return UserBlogDirectoryData(
        scope: query.scope,
        order: null,
        items: const <UserBlogSummary>[],
        pagination: UserBlogPagination(currentPage: query.page),
      );
    }
    if (query.page == 2) {
      return const UserBlogDirectoryData(
        scope: UserBlogFeedScope.public,
        order: UserBlogOrder.latest,
        items: <UserBlogSummary>[
          UserBlogSummary(
            blogId: '117600',
            ownerUserId: '257582',
            title: '第二页日志',
          ),
        ],
        pagination: UserBlogPagination(
          currentPage: 2,
          totalPages: 2,
          hasPrevious: true,
          hasNext: false,
        ),
      );
    }
    final recommended = query.order == UserBlogOrder.recommended;
    return UserBlogDirectoryData(
      scope: UserBlogFeedScope.public,
      order: query.order ?? UserBlogOrder.latest,
      items: <UserBlogSummary>[
        UserBlogSummary(
          blogId: recommended ? '117548' : '117558',
          ownerUserId: '257582',
          title: recommended ? '我们小区的公共交通极其不便利' : '一种体验',
          authorName: recommended ? 'hsyhlj' : '抉择',
          excerpt: '作为女生，见血是常有的事',
          publishedAtText: '2026-6-21 13:06',
        ),
      ],
      pagination: const UserBlogPagination(
        currentPage: 1,
        totalPages: 2,
        hasPrevious: false,
        hasNext: true,
      ),
    );
  }
}

class _FakeBlogDetailRepository implements UserBlogDetailRepository {
  _FakeBlogDetailRepository({UserBlogDetailReadCapabilities? capabilities})
    : readCapabilities = capabilities ?? _detailCapabilities();

  final UserBlogDetailReadCapabilities readCapabilities;
  final List<UserBlogDetailQuery> queries = <UserBlogDetailQuery>[];

  @override
  UserBlogDetailSourceCapabilities get capabilities =>
      UserBlogDetailSourceCapabilities(values: readCapabilities.values);

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: UserBlogDetailData(
        blogId: query.blogId,
        ownerUserId: query.ownerUserId,
        title: '我们小区的公共交通极其不便利',
        bodyHtml: '<p>一直对着电脑屏幕</p>',
        authorName: 'hsyhlj',
        publishedAtText: '2026-6-18 00:25',
        viewCount: 39,
        commentCount: 1,
        commentsOpen: true,
        comments: const <UserBlogComment>[
          UserBlogComment(
            commentId: '646846',
            authorName: 'thessky',
            bodyHtml: '<p>探险的感觉</p>',
            publishedAtText: '2026-6-18 01:00',
          ),
        ],
      ),
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}
