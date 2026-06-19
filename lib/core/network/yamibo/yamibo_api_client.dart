import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';

class YamiboApiClient {
  const YamiboApiClient({required YamiboHttpGateway gateway})
    : _gateway = gateway;

  final YamiboHttpGateway _gateway;

  Future<ApiResult<DiscuzResponse>> getDiscuz({
    required String module,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool treatMessageAsBusinessError = true,
  }) async {
    final result = await _gateway.getJson(
      _buildApiUri(module: module, queryParameters: queryParameters),
      context: YamiboRequestContext(
        kind: YamiboRequestKind.api,
        operation: module,
        module: module,
      ),
      headers: _apiHeaders,
      cancelToken: cancelToken,
    );
    return result.when(
      success: (response) => _parseDiscuzResponse(
        response.body,
        statusCode: response.statusCode,
        treatMessageAsBusinessError: treatMessageAsBusinessError,
      ),
      failure: ApiFailure.new,
    );
  }

  Future<ApiResult<DiscuzResponse>> postDiscuzForm({
    required String module,
    required Map<String, String> data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) async {
    final result = await _gateway.postFormJson(
      _buildApiUri(module: module, queryParameters: queryParameters),
      context: YamiboRequestContext(
        kind: YamiboRequestKind.api,
        operation: module,
        module: module,
      ),
      data: data,
      headers: _mergeHeaders(_apiHeaders, options?.headers),
      cancelToken: cancelToken,
      options: options,
    );
    return result.when(
      success: (response) => _parseDiscuzResponse(
        response.body,
        statusCode: response.statusCode,
        treatMessageAsBusinessError: false,
      ),
      failure: ApiFailure.new,
    );
  }

  Uri _buildApiUri({
    required String module,
    Map<String, dynamic>? queryParameters,
  }) {
    final merged = <String, dynamic>{'module': module, ...?queryParameters};
    merged['version'] = merged['version'] ?? AppConfig.defaultApiVersion;
    return Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: {
        for (final entry in merged.entries) entry.key: entry.value.toString(),
      },
    );
  }

  ApiResult<DiscuzResponse> _parseDiscuzResponse(
    Object? body, {
    required int? statusCode,
    required bool treatMessageAsBusinessError,
  }) {
    try {
      final json = _toJsonMap(body);
      final discuzResponse = DiscuzResponse.fromJson(json);
      if (treatMessageAsBusinessError && discuzResponse.hasBusinessError) {
        return ApiFailure(
          ApiError(
            type: ApiErrorType.business,
            code: discuzResponse.businessCode,
            message: discuzResponse.businessMessage,
            raw: json,
            statusCode: statusCode,
          ),
        );
      }
      return ApiSuccess(discuzResponse);
    } on FormatException catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.parse,
          message: '响应格式错误: ${error.message}',
          raw: error.source,
        ),
      );
    } catch (error) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.unknown,
          message: '未知错误: $error',
          raw: error,
        ),
      );
    }
  }

  Map<String, dynamic> _toJsonMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map(
        (key, dynamic value) => MapEntry(key.toString(), value),
      );
    }
    if (data is! String) {
      throw FormatException('无法解析响应类型: ${data.runtimeType}', data);
    }

    final normalized = _normalizeJsonText(data);
    final firstJsonChar = normalized.isEmpty ? '' : normalized[0];
    if (firstJsonChar != '{' && firstJsonChar != '[') {
      throw FormatException(
        '响应不是JSON文本，开头为: ${_previewResponseStart(normalized)}',
        data,
      );
    }

    final decoded = jsonDecode(normalized);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, dynamic value) => MapEntry(key.toString(), value),
      );
    }
    throw FormatException('响应不是JSON对象', data);
  }

  String _normalizeJsonText(String data) {
    var text = data;
    while (text.isNotEmpty) {
      final trimmed = text.trimLeft();
      if (trimmed.length != text.length) {
        text = trimmed;
        continue;
      }
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
        continue;
      }
      // Some servers/proxies expose UTF-8 BOM bytes after a lossy decode.
      if (text.startsWith('ï»¿')) {
        text = text.substring(3);
        continue;
      }
      break;
    }
    return text;
  }

  String _previewResponseStart(String data) {
    final compact = data.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return '<empty>';
    }
    const maxLength = 80;
    if (compact.length <= maxLength) {
      return compact;
    }
    return '${compact.substring(0, maxLength)}...';
  }

  Map<String, String> _mergeHeaders(
    Map<String, String> base,
    Map<String, dynamic>? extra,
  ) {
    if (extra == null || extra.isEmpty) {
      return base;
    }
    return <String, String>{
      ...base,
      for (final entry in extra.entries) entry.key: entry.value.toString(),
    };
  }

  static const Map<String, String> _apiHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
  };
}
