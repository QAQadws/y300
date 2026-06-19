import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

class YamiboHtmlClient {
  const YamiboHtmlClient({
    required YamiboHttpGateway gateway,
  }) : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  Future<ApiResult<String>> getMobilePage({
    required String path,
    Map<String, String> queryParameters = const <String, String>{},
    required YamiboRequestContext context,
    Uri? referer,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final result = await _gateway.getText(
      uri,
      context: context,
      headers: <String, String>{
        'User-Agent': DiscuzImageRequestHeaderBuilder.mobileBrowserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Referer': (referer ?? Uri.parse('${AppConfig.siteBaseUrl}/')).toString(),
      },
      cancelToken: cancelToken,
    );
    return result.when(
      success: (response) => ApiSuccess(response.body),
      failure: ApiFailure.new,
    );
  }
}
