import 'package:dio/dio.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/utils/parse_utils.dart';

class LoginRequest {
  const LoginRequest({
    required this.username,
    required this.password,
    required this.formhash,
    this.loginField = 'auto',
    this.cookieTime = '1',
    this.questionId = '0',
    this.answer = '',
  });

  final String username;
  final String password;
  final String formhash;
  final String loginField;
  final String cookieTime;
  final String questionId;
  final String answer;

  Map<String, String> toFormData() {
    return <String, String>{
      'formhash': formhash,
      'loginsubmit': '1',
      'username': username,
      'password': password,
      'loginfield': loginField,
      'cookietime': cookieTime,
      if (questionId.trim().isNotEmpty) 'questionid': questionId,
      if (answer.trim().isNotEmpty) 'answer': answer,
    };
  }
}

enum LogoutMode { standard, mobileHash }

abstract class AuthRemoteDataSource {
  Future<ApiResult<DiscuzResponse>> login(LoginRequest request);

  Future<ApiResult<DiscuzResponse>> logout({
    required String formhash,
    LogoutMode mode = LogoutMode.standard,
  });
}

class DiscuzMobileAuthApi implements AuthRemoteDataSource {
  DiscuzMobileAuthApi(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<DiscuzResponse>> login(LoginRequest request) async {
    final validationError = _validateLoginRequest(request);
    if (validationError != null) {
      return ApiFailure<DiscuzResponse>(validationError);
    }

    final result = await _apiClient.postDiscuzForm(
      module: 'login',
      queryParameters: const <String, String>{'action': 'login'},
      data: request.toFormData(),
      options: Options(
        headers: const <String, String>{
          'accept': 'application/json, text/plain, */*',
        },
      ),
    );

    return result.when(
      success: _normalizeLoginResponse,
      failure: ApiFailure.new,
    );
  }

  @override
  Future<ApiResult<DiscuzResponse>> logout({
    required String formhash,
    LogoutMode mode = LogoutMode.standard,
  }) async {
    final normalizedFormhash = formhash.trim();
    if (normalizedFormhash.isEmpty) {
      return const ApiFailure<DiscuzResponse>(
        ApiError(type: ApiErrorType.business, message: 'formhash 为空，无法登出'),
      );
    }

    final query = switch (mode) {
      LogoutMode.standard => <String, String>{
        'action': 'logout',
        'formhash': normalizedFormhash,
      },
      LogoutMode.mobileHash => <String, String>{
        'mlogout': '1',
        'hash': normalizedFormhash,
      },
    };

    final result = await _apiClient.getDiscuz(
      module: 'login',
      queryParameters: query,
      treatMessageAsBusinessError: false,
    );
    return result.when(
      success: _normalizeLogoutResponse,
      failure: ApiFailure.new,
    );
  }

  ApiError? _validateLoginRequest(LoginRequest request) {
    if (request.username.trim().isEmpty || request.password.isEmpty) {
      return const ApiError(type: ApiErrorType.business, message: '用户名和密码不能为空');
    }
    if (request.formhash.trim().isEmpty) {
      return const ApiError(
        type: ApiErrorType.business,
        message: 'formhash 为空，无法登录',
      );
    }
    return null;
  }

  ApiResult<DiscuzResponse> _normalizeLoginResponse(DiscuzResponse response) {
    return _normalizeAuthResponse(
      response,
      successWhenMessageMatches: _isLoginSuccess,
      fallbackMessage: '登录失败',
    );
  }

  ApiResult<DiscuzResponse> _normalizeLogoutResponse(DiscuzResponse response) {
    return _normalizeAuthResponse(
      response,
      successWhenMessageMatches: _isLogoutSuccess,
      fallbackMessage: '登出失败',
    );
  }

  ApiResult<DiscuzResponse> _normalizeAuthResponse(
    DiscuzResponse response, {
    required bool Function(String code, String message)
    successWhenMessageMatches,
    required String fallbackMessage,
  }) {
    final message = response.message;
    if (message == null) {
      return ApiSuccess<DiscuzResponse>(response);
    }

    final code = ParseUtils.asString(message['messageval']);
    final text = ParseUtils.asString(
      message['messagestr'],
      fallback: code.isEmpty ? fallbackMessage : code,
    );
    if (successWhenMessageMatches(code, text)) {
      return ApiSuccess<DiscuzResponse>(response);
    }

    return ApiFailure<DiscuzResponse>(
      ApiError(
        type: ApiErrorType.business,
        code: code.isEmpty ? null : code,
        message: text,
        raw: message,
      ),
    );
  }

  bool _isLoginSuccess(String code, String message) {
    final normalizedCode = code.toLowerCase();
    final normalizedMessage = message.toLowerCase();
    return normalizedCode.contains('succeed') ||
        normalizedCode.contains('success') ||
        normalizedCode.contains('login_succeed') ||
        normalizedMessage.contains('succeed') ||
        normalizedMessage.contains('success') ||
        normalizedMessage.contains('登录成功') ||
        normalizedMessage.contains('欢迎回来') ||
        normalizedMessage.contains('欢迎您回来');
  }

  bool _isLogoutSuccess(String code, String message) {
    final normalizedCode = code.toLowerCase();
    final normalizedMessage = message.toLowerCase();
    return normalizedCode.contains('succeed') ||
        normalizedCode.contains('success') ||
        normalizedCode.contains('logout_succeed') ||
        normalizedMessage.contains('succeed') ||
        normalizedMessage.contains('success') ||
        normalizedMessage.contains('退出成功') ||
        normalizedMessage.contains('登出成功');
  }
}
