import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/forum_home_html_parser.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/models/forum_home_html_models.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';

/// 论坛首页聚合结果：把论坛首页基础数据与登录态相关扩展信息统一返回。
class ForumHomePayload {
  ForumHomePayload({
    required this.forumIndex,
    required this.isLoggedIn,
    required this.favoriteForums,
    this.chromeData = ForumHomeChromeData.empty,
  });

  final ForumIndexData forumIndex;
  final bool isLoggedIn;
  final List<FavoriteForum> favoriteForums;
  final ForumHomeChromeData chromeData;
}

abstract class ForumHomeRepository {
  Future<ApiResult<ForumHomePayload>> getForumHomePayload();
}

/// HTML-first 论坛首页仓库。
///
/// N-2 起原生首页初始渲染只依赖移动端首页 HTML；旧 API 聚合仓库继续保留，
/// 但不再作为 provider 默认实现。
class ForumHomeHtmlRepository implements ForumHomeRepository {
  ForumHomeHtmlRepository({
    required YamiboHtmlClient htmlClient,
    required ForumHomeCarouselImageProbe imageProbe,
    ForumHomeHtmlParser parser = const ForumHomeHtmlParser(),
  }) : _htmlClient = htmlClient,
       _imageProbe = imageProbe,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ForumHomeCarouselImageProbe _imageProbe;
  final ForumHomeHtmlParser _parser;

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/index.php',
      queryParameters: const <String, String>{'mobile': '2'},
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'forum.home.html',
        pageKind: 'forum.home',
      ),
    );
    if (htmlResult case ApiFailure<String>(:final error)) {
      return ApiFailure(
        ApiError(
          type: error.type,
          message: '论坛首页 HTML 加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }

    try {
      final htmlData = _parser.parse(htmlResult.dataOrNull ?? '');
      final resolved = await _withResolvedCarouselAspectRatio(htmlData);
      return ApiSuccess(_toPayload(resolved));
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '论坛首页 HTML 解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  Future<ForumHomeHtmlData> _withResolvedCarouselAspectRatio(
    ForumHomeHtmlData data,
  ) async {
    if (data.carouselItems.isEmpty) {
      return data;
    }
    final firstItem = data.carouselItems.first;
    final aspectRatio = await _imageProbe.resolveAspectRatio(
      firstItem.imageUrl,
    );
    if (aspectRatio == null) {
      return data;
    }
    return ForumHomeHtmlData(
      carouselItems: [
        firstItem.copyWith(aspectRatio: aspectRatio),
        ...data.carouselItems.skip(1),
      ],
      sections: data.sections,
    );
  }

  ForumHomePayload _toPayload(ForumHomeHtmlData data) {
    final regularSections = data.sections
        .where((section) => !section.isFavoriteSection)
        .toList(growable: false);
    final regularForums = [
      for (final section in regularSections)
        for (final item in section.items) _toForumItem(item),
    ];
    final categories = [
      for (var index = 0; index < regularSections.length; index++)
        ForumCategory(
          fid: 'html-${index + 1}',
          name: regularSections[index].title,
          forums: [for (final item in regularSections[index].items) item.fid],
        ),
    ];

    final favoriteItems = [
      for (final section in data.sections)
        if (section.isFavoriteSection)
          for (final item in section.items) item,
    ];

    return ForumHomePayload(
      forumIndex: ForumIndexData(categories: categories, forums: regularForums),
      isLoggedIn: favoriteItems.isNotEmpty,
      favoriteForums: [
        for (final item in favoriteItems) _toFavoriteForum(item),
      ],
      chromeData: ForumHomeChromeData(
        carouselItems: data.carouselItems,
        favoriteForums: [
          for (final item in favoriteItems) _toChromeForumItem(item),
        ],
      ),
    );
  }

  ForumItem _toForumItem(ForumHomeHtmlForumItem item) {
    return ForumItem(
      fid: item.fid,
      name: item.title,
      threads: 0,
      posts: 0,
      todayPosts: item.todayPosts,
      description: item.description,
      icon: item.iconUrl ?? '',
      subForums: const <ForumItem>[],
    );
  }

  FavoriteForum _toFavoriteForum(ForumHomeHtmlForumItem item) {
    return FavoriteForum(
      favid: 'html-${item.fid}',
      fid: item.fid,
      title: item.title,
      description: item.description,
      threads: 0,
      posts: 0,
      todayPosts: item.todayPosts,
    );
  }

  ForumHomeChromeForumItem _toChromeForumItem(ForumHomeHtmlForumItem item) {
    return ForumHomeChromeForumItem(
      fid: item.fid,
      title: item.title,
      description: item.description,
      todayPosts: item.todayPosts,
    );
  }
}

/// Discuz 论坛首页聚合仓库。
///
/// 约定：
/// 1) forumindex 是首页主数据，失败则整体失败。
/// 2) profile 仅用于判断登录态。
/// 3) 版块收藏只是论坛首页的快捷入口，线程收藏仍统一走收藏 Tab。
class DiscuzForumHomeRepository implements ForumHomeRepository {
  DiscuzForumHomeRepository({
    required Future<ApiResult<ForumIndexData>> Function() loadForumIndex,
    required Future<ApiResult<SessionInfo>> Function() refreshSession,
    Future<ApiResult<List<FavoriteForum>>> Function()? loadFavoriteForums,
    Future<ApiResult<ForumHomeChromeData>> Function()? loadChrome,
  }) : _loadForumIndex = loadForumIndex,
       _refreshSession = refreshSession,
       _loadFavoriteForums = loadFavoriteForums,
       _loadChrome = loadChrome;

  final Future<ApiResult<ForumIndexData>> Function() _loadForumIndex;
  final Future<ApiResult<SessionInfo>> Function() _refreshSession;
  final Future<ApiResult<List<FavoriteForum>>> Function()? _loadFavoriteForums;
  final Future<ApiResult<ForumHomeChromeData>> Function()? _loadChrome;

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
    final forumResult = await _loadForumIndex();
    if (forumResult.isFailure) {
      return ApiFailure<ForumHomePayload>(forumResult.errorOrNull!);
    }

    final forumIndex = forumResult.dataOrNull!;
    final sessionResult = await _refreshSession();

    final isLoggedIn = sessionResult.when(
      success: (session) => session.isLoggedIn,
      failure: (_) => false,
    );
    final favoriteForums = isLoggedIn
        ? await _safeLoadFavoriteForums()
        : const <FavoriteForum>[];
    final chromeData = await _safeLoadChrome();

    return ApiSuccess(
      ForumHomePayload(
        forumIndex: forumIndex,
        isLoggedIn: isLoggedIn,
        favoriteForums: favoriteForums,
        chromeData: chromeData,
      ),
    );
  }

  Future<List<FavoriteForum>> _safeLoadFavoriteForums() async {
    final loader = _loadFavoriteForums;
    if (loader == null) {
      return const <FavoriteForum>[];
    }
    final result = await loader();
    return result.when(
      success: (forums) => forums,
      failure: (_) => const <FavoriteForum>[],
    );
  }

  Future<ForumHomeChromeData> _safeLoadChrome() async {
    final loader = _loadChrome;
    if (loader == null) {
      return ForumHomeChromeData.empty;
    }
    final result = await loader();
    return result.when(
      success: (chrome) => chrome,
      failure: (_) => ForumHomeChromeData.empty,
    );
  }
}

final forumHomeRepositoryProvider = Provider<ForumHomeRepository>((ref) {
  return ForumHomeHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: ref.watch(yamiboResourceClientProvider),
      headerBuilder: ref.watch(imageRequestHeaderBuilderProvider),
    ),
  );
});
