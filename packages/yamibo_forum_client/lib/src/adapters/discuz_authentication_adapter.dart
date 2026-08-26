import '../contracts/data_command_contract.dart';
import '../contracts/forum_authentication.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_cookie_store.dart';
import '../session/forum_formhash_provider.dart';
import '../session/forum_session_store.dart';
import 'discuz_api_client.dart';

/// Experimental Discuz v4 implementation of the authentication contracts.
final class DiscuzAuthenticationAdapter
    implements ForumSessionRepository, ForumPasswordLoginCommand {
  /// Creates an adapter over one shared transport and Cookie/session boundary.
  const DiscuzAuthenticationAdapter(
    this._api,
    this._formhash,
    this._sessions,
    this._cookies,
  );

  final DiscuzApiClient _api;
  final ForumFormhashProvider _formhash;
  final ForumSessionStore _sessions;
  final ForumCookieStore? _cookies;

  @override
  Future<ForumSessionResult> resolve([
    ForumSessionRequest request = const ForumSessionRequest(),
  ]) async {
    final response = await _api.get(
      module: 'profile',
      treatMessageAsBusinessError: false,
      cancellation: request.cancellation,
    );
    return switch (response) {
      ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(:final failure) =>
        ForumSessionInconclusive(_failureFromTransport(failure)),
      ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
        :final response,
      ) =>
        await _resolveProfile(response.body.variables),
    };
  }

  @override
  Future<DataCommandResult<ForumLoginReceipt>> execute(
    ForumPasswordLoginRequest request,
  ) async {
    final username = request.username.trim();
    if (username.isEmpty || request.password.isEmpty) {
      return const DataCommandNotSent<ForumLoginReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.afterInputChange,
          code: 'credentials_required',
          diagnosticMessage: 'credentials_required',
        ),
      );
    }
    if (_cookies == null) {
      return const DataCommandUnsupported<ForumLoginReceipt>();
    }
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent<ForumLoginReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'request_cancelled',
          diagnosticMessage: 'request_cancelled',
        ),
      );
    }

    final formhashResult = await _formhash.loadFormhash(
      preferProfile: false,
      cancellation: request.cancellation,
    );
    final formhash = switch (formhashResult) {
      ForumFormhashSuccess(:final value) => value.trim(),
      ForumFormhashError() => '',
    };
    if (formhash.isEmpty) {
      final failure = switch (formhashResult) {
        ForumFormhashError(:final failure) => _failureFromTransport(
          failure,
          defaultRetry: DataCommandRetryPolicy.afterSessionRefresh,
        ),
        _ => const DataCommandFailure(
          kind: DataCommandFailureKind.staleFormhash,
          retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
          code: 'formhash_unavailable',
          diagnosticMessage: 'formhash_unavailable',
        ),
      };
      return DataCommandNotSent<ForumLoginReceipt>(failure);
    }

    final security = request.securityAnswer;
    final response = await _api.postForm(
      module: 'login',
      queryParameters: const <String, Object?>{'action': 'login'},
      form: <String, String>{
        'formhash': formhash,
        'loginsubmit': '1',
        'username': username,
        'password': request.password,
        'loginfield': 'auto',
        'cookietime': '1',
        'questionid': security?.questionId.trim().isNotEmpty == true
            ? security!.questionId.trim()
            : '0',
        'answer': security?.answer ?? '',
      },
      treatMessageAsBusinessError: false,
      cancellation: request.cancellation,
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown<ForumLoginReceipt>(
        _failureFromTransport(failure),
      );
    }
    final envelope =
        (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response
            .body;
    final message = envelope.message;
    if (message == null) {
      return const DataCommandOutcomeUnknown<ForumLoginReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'login_success_unproven',
          diagnosticMessage: 'login_success_unproven',
        ),
      );
    }
    if (!_isSuccessMessage(message, login: true)) {
      return DataCommandRejected<ForumLoginReceipt>(
        _failureFromMessage(message, login: true),
      );
    }

    final verified = await resolve(
      ForumSessionRequest(cancellation: request.cancellation),
    );
    return switch (verified) {
      ForumSessionAuthenticated(:final identity) =>
        DataCommandApplied<ForumLoginReceipt>(ForumLoginReceipt(identity)),
      ForumSessionAnonymous() => const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unauthenticated,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'login_session_not_applied',
          diagnosticMessage: 'login_session_not_applied',
        ),
      ),
      ForumSessionInconclusive(:final failure) =>
        DataCommandOutcomeUnknown<ForumLoginReceipt>(failure),
    };
  }

  /// Performs the standard Discuz logout for [DiscuzLogoutCommandAdapter].
  Future<DataCommandResult<ForumLogoutReceipt>> performLogout([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]) async {
    if (_cookies == null) {
      return const DataCommandUnsupported<ForumLogoutReceipt>();
    }
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent<ForumLogoutReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'request_cancelled',
          diagnosticMessage: 'request_cancelled',
        ),
      );
    }
    final formhashResult = await _formhash.loadFormhash(
      preferProfile: true,
      cancellation: request.cancellation,
    );
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent<ForumLogoutReceipt>(
        _failureFromTransport(
          failure,
          defaultRetry: DataCommandRetryPolicy.afterSessionRefresh,
        ),
      );
    }
    final formhash = (formhashResult as ForumFormhashSuccess).value.trim();
    if (formhash.isEmpty) {
      return const DataCommandNotSent<ForumLogoutReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.staleFormhash,
          retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
          code: 'formhash_unavailable',
          diagnosticMessage: 'formhash_unavailable',
        ),
      );
    }
    final response = await _api.get(
      module: 'login',
      queryParameters: <String, Object?>{
        'action': 'logout',
        'formhash': formhash,
      },
      treatMessageAsBusinessError: false,
      cancellation: request.cancellation,
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown<ForumLogoutReceipt>(
        _failureFromTransport(failure),
      );
    }
    final envelope =
        (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response
            .body;
    final message = envelope.message;
    if (message == null || !_isSuccessMessage(message, login: false)) {
      return DataCommandRejected<ForumLogoutReceipt>(
        message == null
            ? const DataCommandFailure(
                kind: DataCommandFailureKind.parse,
                retryPolicy: DataCommandRetryPolicy.explicitOnly,
                code: 'logout_success_unproven',
                diagnosticMessage: 'logout_success_unproven',
              )
            : _failureFromMessage(message, login: false),
      );
    }
    var cleanupFailed = false;
    try {
      await _cookies.clear();
    } on Object {
      cleanupFailed = true;
    }
    try {
      await _sessions.clear();
    } on Object {
      cleanupFailed = true;
    }
    if (cleanupFailed) {
      return const DataCommandOutcomeUnknown<ForumLogoutReceipt>(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'logout_local_cleanup_failed',
          diagnosticMessage: 'logout_local_cleanup_failed',
        ),
      );
    }
    return const DataCommandApplied<ForumLogoutReceipt>(ForumLogoutReceipt());
  }

  Future<ForumSessionResult> _resolveProfile(
    Map<String, Object?> variables,
  ) async {
    final userId = _firstNonEmpty(<Object?>[
      variables['member_uid'],
      _asMap(variables['space'])['uid'],
    ]);
    final username = _firstNonEmpty(<Object?>[
      variables['member_username'],
      _asMap(variables['space'])['username'],
    ]);
    final formhash = variables['formhash']?.toString().trim() ?? '';
    final now = DateTime.now();
    final numericUserId = int.tryParse(userId);
    if (numericUserId == 0) {
      await _mergeAuthoritative(
        ForumSessionSnapshot(
          isLoggedIn: false,
          userId: '0',
          username: '',
          formhash: formhash,
          updatedAt: now,
          formhashUpdatedAt: formhash.isEmpty ? null : now,
          source: 'auth:profile',
        ),
      );
      return const ForumSessionAnonymous();
    }
    if (numericUserId == null || numericUserId < 1) {
      return const ForumSessionInconclusive(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'profile_identity_unproven',
          diagnosticMessage: 'profile_identity_unproven',
        ),
      );
    }
    await _mergeAuthoritative(
      ForumSessionSnapshot(
        isLoggedIn: true,
        userId: userId,
        username: username,
        formhash: formhash,
        updatedAt: now,
        formhashUpdatedAt: formhash.isEmpty ? null : now,
        source: 'auth:profile',
      ),
    );
    return ForumSessionAuthenticated(
      ForumSessionIdentity(userId: userId, username: username),
    );
  }

  Future<void> _mergeAuthoritative(ForumSessionSnapshot snapshot) async {
    try {
      await _sessions.merge(snapshot);
    } on Object {
      // The session projection is reproducible. A Host persistence failure
      // must not invalidate a session identity proved by the server.
    }
  }

  DataCommandFailure _failureFromTransport(
    ForumTransportFailure failure, {
    DataCommandRetryPolicy defaultRetry = DataCommandRetryPolicy.explicitOnly,
  }) {
    final security = failure.statusCode == 405;
    final kind = security
        ? DataCommandFailureKind.securityChallenge
        : switch (failure.kind) {
            ForumTransportFailureKind.network => DataCommandFailureKind.network,
            ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
            ForumTransportFailureKind.server => DataCommandFailureKind.server,
            ForumTransportFailureKind.unauthorized =>
              DataCommandFailureKind.unauthenticated,
            ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
            ForumTransportFailureKind.business =>
              DataCommandFailureKind.unknown,
            ForumTransportFailureKind.cancelled =>
              DataCommandFailureKind.cancelled,
            ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
          };
    return DataCommandFailure(
      kind: kind,
      retryPolicy: defaultRetry,
      code: failure.code,
      statusCode: failure.statusCode,
      diagnosticMessage: failure.code,
    );
  }

  DataCommandFailure _failureFromMessage(
    Map<String, Object?> message, {
    required bool login,
  }) {
    final code = message['messageval']?.toString().trim();
    final normalized = code?.toLowerCase() ?? '';
    final kind =
        normalized.contains('password') ||
            normalized.contains('login') ||
            normalized.contains('question')
        ? DataCommandFailureKind.unauthenticated
        : normalized.contains('formhash')
        ? DataCommandFailureKind.staleFormhash
        : DataCommandFailureKind.permissionDenied;
    return DataCommandFailure(
      kind: kind,
      retryPolicy: login
          ? DataCommandRetryPolicy.afterInputChange
          : kind == DataCommandFailureKind.staleFormhash
          ? DataCommandRetryPolicy.afterSessionRefresh
          : DataCommandRetryPolicy.explicitOnly,
      code: code?.isNotEmpty == true ? code : 'discuz_command_rejected',
      diagnosticMessage: code?.isNotEmpty == true
          ? code!
          : 'discuz_command_rejected',
    );
  }

  bool _isSuccessMessage(Map<String, Object?> message, {required bool login}) {
    final code = message['messageval']?.toString().trim().toLowerCase() ?? '';
    final text = message['messagestr']?.toString().trim().toLowerCase() ?? '';
    final action = login ? 'login' : 'logout';
    return code.contains('succeed') ||
        code.contains('success') ||
        code.contains('${action}_succeed') ||
        text.contains('succeed') ||
        text.contains('success') ||
        (login && (text.contains('登录成功') || text.contains('欢迎回来'))) ||
        (!login && (text.contains('退出成功') || text.contains('登出成功')));
  }

  Map<String, Object?> _asMap(Object? value) => value is Map
      ? <String, Object?>{
          for (final entry in value.entries) entry.key.toString(): entry.value,
        }
      : const <String, Object?>{};

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}

/// Experimental standard-logout command sharing one authentication core.
final class DiscuzLogoutCommandAdapter implements ForumLogoutCommand {
  /// Creates a logout view over the shared authentication adapter.
  const DiscuzLogoutCommandAdapter(this._delegate);

  final DiscuzAuthenticationAdapter _delegate;

  @override
  Future<DataCommandResult<ForumLogoutReceipt>> execute([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]) => _delegate.performLogout(request);
}
