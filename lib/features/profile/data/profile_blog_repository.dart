import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/profile_blog_html_parser.dart';

abstract class ProfileBlogRepository {
  Future<ApiResult<ProfileBlogListPageData>> getBlogList({
    ProfileBlogView view = ProfileBlogView.all,
    ProfileBlogOrder order = ProfileBlogOrder.latest,
    int page = 1,
  });

  Future<ApiResult<ProfileBlogDetailData>> getBlogDetail({required String url});
}

class YamiboProfileBlogRepository implements ProfileBlogRepository {
  const YamiboProfileBlogRepository({
    required YamiboHtmlClient htmlClient,
    ProfileBlogHtmlParser parser = const ProfileBlogHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ProfileBlogHtmlParser _parser;

  @override
  Future<ApiResult<ProfileBlogListPageData>> getBlogList({
    ProfileBlogView view = ProfileBlogView.all,
    ProfileBlogOrder order = ProfileBlogOrder.latest,
    int page = 1,
  }) async {
    final queryParameters = <String, String>{
      'mod': 'space',
      'do': 'blog',
      'view': view.queryValue,
      'mobile': '2',
      if (view == ProfileBlogView.all && order == ProfileBlogOrder.hot)
        'order': order.queryValue,
      if (page > 1) 'page': page.toString(),
    };
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: queryParameters,
      context: YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'profile.blog.list',
        module: 'profile',
        pageKind: 'profile.blog.list.${view.queryValue}',
      ),
    );
    return htmlResult.when(
      success: (html) {
        try {
          return ApiSuccess<ProfileBlogListPageData>(
            _parser.parseList(html, fallbackView: view, fallbackOrder: order),
          );
        } catch (error) {
          return ApiFailure<ProfileBlogListPageData>(
            ApiError(
              type: ApiErrorType.parse,
              message: '日志列表解析失败: $error',
              raw: error,
            ),
          );
        }
      },
      failure: (error) => ApiFailure<ProfileBlogListPageData>(
        ApiError(
          type: error.type,
          message: '日志列表加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      ),
    );
  }

  @override
  Future<ApiResult<ProfileBlogDetailData>> getBlogDetail({
    required String url,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return const ApiFailure<ProfileBlogDetailData>(
        ApiError(type: ApiErrorType.business, message: '日志链接缺失'),
      );
    }
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) {
      return const ApiFailure<ProfileBlogDetailData>(
        ApiError(type: ApiErrorType.business, message: '日志链接无效'),
      );
    }
    final htmlResult = await _htmlClient.getMobilePage(
      path: uri.path.startsWith('/') ? uri.path : '/${uri.path}',
      queryParameters: <String, String>{...uri.queryParameters, 'mobile': '2'},
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'profile.blog.detail',
        module: 'profile',
        pageKind: 'profile.blog.detail',
      ),
    );
    return htmlResult.when(
      success: (html) {
        try {
          return ApiSuccess<ProfileBlogDetailData>(
            _parser.parseDetail(html, fallbackUrl: normalizedUrl),
          );
        } catch (error) {
          return ApiFailure<ProfileBlogDetailData>(
            ApiError(
              type: ApiErrorType.parse,
              message: '日志详情解析失败: $error',
              raw: error,
            ),
          );
        }
      },
      failure: (error) => ApiFailure<ProfileBlogDetailData>(
        ApiError(
          type: error.type,
          message: '日志详情加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      ),
    );
  }
}

final profileBlogRepositoryProvider = Provider<ProfileBlogRepository>((ref) {
  return YamiboProfileBlogRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
  );
});
