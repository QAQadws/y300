import 'package:dio/dio.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

class YamiboResourceClient {
  const YamiboResourceClient({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  Future<ApiResult<List<int>>> getBytes({
    required String url,
    required YamiboRequestContext context,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const ApiFailure(
        ApiError(type: ApiErrorType.network, message: '资源地址无效'),
      );
    }

    final result = await _gateway.getBytes(
      uri,
      context: context,
      headers: headers,
      cancelToken: cancelToken,
    );
    return result.when(
      success: (response) => ApiSuccess(response.body),
      failure: ApiFailure.new,
    );
  }
}
