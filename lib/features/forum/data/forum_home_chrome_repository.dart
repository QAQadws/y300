import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/data/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/forum_home_chrome_parser.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';

abstract class ForumHomeChromeRepository {
  Future<ApiResult<ForumHomeChromeData>> loadChrome();
}

class DiscuzForumHomeChromeRepository implements ForumHomeChromeRepository {
  DiscuzForumHomeChromeRepository({
    required CookieStore cookieStore,
    ForumHomeCarouselImageProbe? imageProbe,
    ForumHomeChromeParser parser = const ForumHomeChromeParser(),
    Dio? dio,
  }) : _cookieStore = cookieStore,
       _imageProbe = imageProbe ?? ForumHomeCarouselImageProbe(dio: dio),
       _parser = parser,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.siteBaseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
               followRedirects: true,
               validateStatus: (status) =>
                   status != null && status >= 200 && status < 400,
               responseType: ResponseType.plain,
             ),
           );

  final CookieStore _cookieStore;
  final ForumHomeCarouselImageProbe _imageProbe;
  final ForumHomeChromeParser _parser;
  final Dio _dio;

  @override
  Future<ApiResult<ForumHomeChromeData>> loadChrome() async {
    ApiFailure<ForumHomeChromeData>? lastFailure;
    ForumHomeChromeData? emptySuccess;
    for (final request in _homeRequests) {
      final result = await _loadChromeFrom(request);
      if (result case ApiSuccess<ForumHomeChromeData>(:final data)) {
        if (data.carouselItems.isNotEmpty) {
          return result;
        }
        emptySuccess ??= data;
        continue;
      }
      if (result case ApiFailure<ForumHomeChromeData>()) {
        lastFailure = result;
      }
    }

    if (emptySuccess != null) {
      return ApiSuccess(emptySuccess);
    }
    return lastFailure ??
        const ApiFailure(
          ApiError(
            type: ApiErrorType.unknown,
            message: '论坛首页外观数据加载失败: no request attempted',
          ),
        );
  }

  Future<ApiResult<ForumHomeChromeData>> _loadChromeFrom(
    _ForumHomeChromeRequest request,
  ) async {
    final uri = request.uri;
    try {
      final headers = await _buildHeaders(uri);
      final response = await _dio.get<String>(
        request.path,
        queryParameters: request.queryParameters.isEmpty
            ? null
            : request.queryParameters,
        options: Options(headers: headers),
      );
      final setCookie = response.headers.map['set-cookie'] ?? const <String>[];
      await _cookieStore.saveFromSetCookie(response.requestOptions.uri, setCookie);
      final html = response.data ?? '';
      final chrome = _parser.parse(html);
      return ApiSuccess(await _withResolvedCarouselAspectRatio(chrome));
    } on DioException catch (error) {
      return ApiFailure(
        ApiError(
          type: _mapDioErrorType(error),
          message: '论坛首页外观数据加载失败: ${error.message ?? 'unknown'}',
          statusCode: error.response?.statusCode,
          raw: error.response?.data,
        ),
      );
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.unknown,
          message: '论坛首页外观数据解析失败: $error',
          raw: error,
        ),
      );
    }
  }

  Future<ForumHomeChromeData> _withResolvedCarouselAspectRatio(
    ForumHomeChromeData chrome,
  ) async {
    if (chrome.carouselItems.isEmpty) {
      return chrome;
    }
    final firstItem = chrome.carouselItems.first;
    final headers = await _buildImageHeaders(firstItem.imageUrl);
    final aspectRatio = await _imageProbe.resolveAspectRatio(
      firstItem.imageUrl,
      headers: headers,
    );
    if (aspectRatio == null) {
      return chrome;
    }
    return chrome.copyWith(
      carouselItems: [
        firstItem.copyWith(aspectRatio: aspectRatio),
        ...chrome.carouselItems.skip(1),
      ],
    );
  }

  Future<Map<String, String>> _buildHeaders(Uri uri) async {
    final headers = <String, String>{
      'User-Agent': DiscuzImageRequestHeaderBuilder.mobileBrowserUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Referer': '${AppConfig.siteBaseUrl}/',
    };
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  Future<Map<String, String>> _buildImageHeaders(String imageUrl) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const <String, String>{};
    }
    final headers = <String, String>{
      'User-Agent': DiscuzImageRequestHeaderBuilder.browserUserAgent,
      'Accept': DiscuzImageRequestHeaderBuilder.imageAcceptHeader,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': '${AppConfig.siteBaseUrl}/',
    };
    final cookieHeader = await _cookieStore.readCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  ApiErrorType _mapDioErrorType(DioException error) {
    final statusCode = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiErrorType.timeout;
    }
    if (statusCode == 401 || statusCode == 403) {
      return ApiErrorType.unauthorized;
    }
    return ApiErrorType.network;
  }

  static final List<_ForumHomeChromeRequest> _homeRequests =
      <_ForumHomeChromeRequest>[
        _ForumHomeChromeRequest(
          path: '/index.php',
          queryParameters: <String, String>{'mobile': '2'},
        ),
      ];
}

class _ForumHomeChromeRequest {
  const _ForumHomeChromeRequest({
    required this.path,
    this.queryParameters = const <String, String>{},
  });

  final String path;
  final Map<String, String> queryParameters;

  Uri get uri {
    final siteRoot = Uri.parse(AppConfig.siteBaseUrl);
    if (queryParameters.isEmpty) {
      return siteRoot.replace(path: path);
    }
    return siteRoot.replace(path: path, queryParameters: queryParameters);
  }
}

final forumHomeChromeRepositoryProvider = Provider<ForumHomeChromeRepository>((
  ref,
) {
  return DiscuzForumHomeChromeRepository(
    cookieStore: ref.watch(cookieStoreProvider),
  );
});
