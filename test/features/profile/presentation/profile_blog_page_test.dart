import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/repositories/profile_blog_repository.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

void main() {
  testWidgets('ProfileBlogPage switches blog tabs and opens detail', (
    tester,
  ) async {
    final repository = _FakeProfileBlogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileBlogRepositoryProvider.overrideWithValue(repository),
          imageRequestHeaderBuilderProvider.overrideWithValue(
            const _StaticImageHeaderBuilder(),
          ),
          imageCacheServiceProvider.overrideWithValue(
            _FailingImageCacheService(),
          ),
        ],
        child: const MaterialApp(home: ProfileBlogPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
    expect(find.byKey(const Key('profile-blog-view-tabs')), findsOneWidget);
    expect(find.text('随便看看'), findsOneWidget);
    expect(find.text('最新发表的日志'), findsOneWidget);
    expect(find.text('一种体验'), findsOneWidget);

    await tester.tap(find.text('推荐阅读的日志'));
    await tester.pumpAndSettle();

    expect(repository.lastOrder, ProfileBlogOrder.hot);
    expect(find.text('我们小区的公共交通极其不便利'), findsOneWidget);

    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();

    expect(repository.lastView, ProfileBlogView.mine);
    expect(find.text('还没有相关的日志'), findsOneWidget);

    await tester.tap(find.text('随便看看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我们小区的公共交通极其不便利'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-blog-detail')), findsOneWidget);
    expect(
      find.text('hsyhlj · 2026-6-18 00:25 · 浏览 39 · 评论 5'),
      findsOneWidget,
    );
    expect(_richTextContaining('一直对着电脑屏幕'), findsOneWidget);
    expect(find.text('日志评论'), findsOneWidget);
    expect(_richTextContaining('探险的感觉'), findsOneWidget);
    expect(find.byType(ThreadPostQuoteBlockView), findsOneWidget);
    expect(_richTextContaining('thessky: 引用正文'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedLibraryImage &&
            widget.request?.role == ImageCacheRole.avatar &&
            widget.request?.sourceUrl.contains('/uc_server/data/avatar/') ==
                true,
      ),
      findsWidgets,
    );
  });
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeProfileBlogRepository implements ProfileBlogRepository {
  ProfileBlogView? lastView;
  ProfileBlogOrder? lastOrder;

  @override
  Future<ApiResult<ProfileBlogListPageData>> getBlogList({
    ProfileBlogView view = ProfileBlogView.all,
    ProfileBlogOrder order = ProfileBlogOrder.latest,
    int page = 1,
  }) async {
    lastView = view;
    lastOrder = order;
    if (view != ProfileBlogView.all) {
      return ApiSuccess<ProfileBlogListPageData>(
        ProfileBlogListPageData(
          title: '日志',
          activeView: view,
          activeOrder: order,
          viewTabs: _viewTabs(view),
          orderTabs: const <ProfileBlogNavigationTab>[],
          items: const <ProfileBlogListItem>[],
          emptyMessage: '还没有相关的日志',
        ),
      );
    }
    final item = order == ProfileBlogOrder.hot ? _hotItem : _latestItem;
    return ApiSuccess<ProfileBlogListPageData>(
      ProfileBlogListPageData(
        title: '日志',
        activeView: ProfileBlogView.all,
        activeOrder: order,
        viewTabs: _viewTabs(ProfileBlogView.all),
        orderTabs: _orderTabs(order),
        items: [item],
        pagination: const ProfileBlogPagination(
          currentPage: 1,
          totalPages: 2,
          nextUrl: 'https://bbs.yamibo.com/home.php?page=2',
        ),
      ),
    );
  }

  @override
  Future<ApiResult<ProfileBlogDetailData>> getBlogDetail({
    required String url,
  }) async {
    return const ApiSuccess<ProfileBlogDetailData>(
      ProfileBlogDetailData(
        id: '117548',
        uid: '257582',
        title: '我们小区的公共交通极其不便利',
        author: 'hsyhlj',
        authorUrl: null,
        avatarUrl:
            'https://bbs.yamibo.com/uc_server/data/avatar/000/25/75/82_avatar_small.jpg',
        dateline: '2026-6-18 00:25',
        views: 39,
        commentsCount: 5,
        messageHtml: '<p>一直对着电脑屏幕</p>',
        actions: <ProfileBlogAction>[],
        comments: [
          ProfileBlogComment(
            id: '646846',
            author: 'thessky',
            authorUrl: null,
            avatarUrl:
                'https://bbs.yamibo.com/uc_server/data/avatar/000/57/74/94_avatar_small.jpg',
            dateline: '2026-6-18 09:39',
            messageHtml:
                '<div class="quote"><blockquote><b>thessky</b>: 引用正文</blockquote></div><p>探险的感觉</p>',
          ),
        ],
      ),
    );
  }

  List<ProfileBlogNavigationTab> _viewTabs(ProfileBlogView activeView) {
    return [
      for (final view in ProfileBlogView.values)
        ProfileBlogNavigationTab(
          label: view.label,
          url: 'https://bbs.yamibo.com/home.php?view=${view.queryValue}',
          isActive: view == activeView,
        ),
    ];
  }

  List<ProfileBlogNavigationTab> _orderTabs(ProfileBlogOrder activeOrder) {
    return [
      for (final order in ProfileBlogOrder.values)
        ProfileBlogNavigationTab(
          label: order.label,
          url: 'https://bbs.yamibo.com/home.php?order=${order.queryValue}',
          isActive: order == activeOrder,
        ),
    ];
  }
}

const _latestItem = ProfileBlogListItem(
  id: '117558',
  uid: '121614',
  title: '一种体验',
  excerpt: '作为女生，见血是常有的事',
  author: '抉择',
  authorUrl: null,
  avatarUrl: null,
  dateline: '2026-6-21 13:06',
  url: 'https://bbs.yamibo.com/home.php?mod=space&uid=121614&do=blog&id=117558',
);

const _hotItem = ProfileBlogListItem(
  id: '117548',
  uid: '257582',
  title: '我们小区的公共交通极其不便利',
  excerpt: '一直对着电脑屏幕',
  author: 'hsyhlj',
  authorUrl: null,
  avatarUrl: null,
  dateline: '2026-6-18 00:25',
  url: 'https://bbs.yamibo.com/home.php?mod=space&uid=257582&do=blog&id=117548',
);

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) {
      return false;
    }
    return widget.text.toPlainText().contains(text);
  });
}
