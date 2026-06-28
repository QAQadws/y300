import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/data/services/forum_home_chrome_parser.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';

abstract class ForumHomeChromeRepository {
  Future<ApiResult<ForumHomeChromeData>> loadChrome();
}

class DiscuzForumHomeChromeRepository implements ForumHomeChromeRepository {
  DiscuzForumHomeChromeRepository({
    required YamiboHtmlClient htmlClient,
    required ForumHomeCarouselImageProbe imageProbe,
    ForumHomeChromeParser parser = const ForumHomeChromeParser(),
  })  : _htmlClient = htmlClient,
        _imageProbe = imageProbe,
        _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ForumHomeCarouselImageProbe _imageProbe;
  final ForumHomeChromeParser _parser;

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
    try {
      final response = await _htmlClient.getMobilePage(
        path: request.path,
        queryParameters: request.queryParameters,
        context: const YamiboRequestContext(
          kind: YamiboRequestKind.html,
          operation: 'forum.home.chrome',
          pageKind: 'forum.home',
        ),
      );
      if (response case ApiFailure<String>(:final error)) {
        return ApiFailure(
          ApiError(
            type: error.type,
            message: '论坛首页外观数据加载失败: ${error.message}',
            code: error.code,
            statusCode: error.statusCode,
            raw: error.raw,
          ),
        );
      }
      final html = response.dataOrNull ?? '';
      final chrome = _parser.parse(html);
      return ApiSuccess(await _withResolvedCarouselAspectRatio(chrome));
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
    final aspectRatio = await _imageProbe.resolveAspectRatio(
      firstItem.imageUrl,
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
}

final forumHomeChromeRepositoryProvider = Provider<ForumHomeChromeRepository>((
  ref,
) {
  return DiscuzForumHomeChromeRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: ref.watch(yamiboResourceClientProvider),
      headerBuilder: ref.watch(imageRequestHeaderBuilderProvider),
    ),
  );
});
