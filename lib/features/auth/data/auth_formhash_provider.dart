import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/utils/parse_utils.dart';

abstract class FormhashProvider {
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false});
}

class ApiFormhashProvider implements FormhashProvider {
  ApiFormhashProvider(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false}) async {
    final modules = preferProfile
        ? const <String>['profile', 'forumindex']
        : const <String>['forumindex', 'profile'];

    ApiError? lastError;
    for (final module in modules) {
      final result = await _apiClient.getDiscuz(module: module);
      if (result case ApiFailure<DiscuzResponse>(:final error)) {
        lastError = error;
        continue;
      }

      final response = (result as ApiSuccess<DiscuzResponse>).data;
      final formhash = ParseUtils.asString(response.variables['formhash']).trim();
      if (formhash.isNotEmpty) {
        return ApiSuccess<String>(formhash);
      }
      lastError = ApiError(
        type: ApiErrorType.business,
        message: '$module.formhash 为空',
        raw: response.variables,
      );
    }

    final error = lastError;
    if (error != null) {
      return ApiFailure<String>(
        ApiError(
          type: error.type,
          message: '获取 formhash 失败：${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      );
    }
    return const ApiFailure<String>(
      ApiError(type: ApiErrorType.business, message: '获取 formhash 失败'),
    );
  }
}

