import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/providers/auth_contract_providers.dart';

/// Legacy-shaped test harness that keeps large widget fixtures concise while
/// production code consumes the three source-neutral package contracts.
abstract class AuthRepository {
  Future<ApiResult<SessionInfo>> refreshSession();

  Future<ApiResult<bool>> verifyAuthByForumIndex();

  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  });

  Future<void> logout();
}

final class SessionInfo {
  const SessionInfo({
    required this.uid,
    required this.username,
    required this.formhash,
    required this.isLoggedIn,
  });

  final String uid;
  final String username;
  final String formhash;
  final bool isLoggedIn;
}

List<Override> forumAuthOverrides(AuthRepository repository) => <Override>[
  forumSessionRepositoryProvider.overrideWithValue(
    _TestSessionRepository(repository),
  ),
  forumPasswordLoginCommandProvider.overrideWithValue(
    _TestLoginCommand(repository),
  ),
  forumLogoutCommandProvider.overrideWithValue(_TestLogoutCommand(repository)),
];

ForumSessionRepository forumSessionRepositoryFrom(AuthRepository repository) =>
    _TestSessionRepository(repository);

final class _TestSessionRepository implements ForumSessionRepository {
  const _TestSessionRepository(this._repository);
  final AuthRepository _repository;

  @override
  Future<ForumSessionResult> resolve([
    ForumSessionRequest request = const ForumSessionRequest(),
  ]) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const ForumSessionInconclusive(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'request_cancelled',
          diagnosticMessage: 'request_cancelled',
        ),
      );
    }
    final result = await _repository.refreshSession();
    return switch (result) {
      ApiSuccess<SessionInfo>(:final data) when data.isLoggedIn =>
        ForumSessionAuthenticated(
          ForumSessionIdentity(userId: data.uid, username: data.username),
        ),
      ApiSuccess<SessionInfo>() => const ForumSessionAnonymous(),
      ApiFailure<SessionInfo>(:final error) => ForumSessionInconclusive(
        _commandFailure(error),
      ),
    };
  }
}

final class _TestLoginCommand implements ForumPasswordLoginCommand {
  const _TestLoginCommand(this._repository);
  final AuthRepository _repository;

  @override
  Future<DataCommandResult<ForumLoginReceipt>> execute(
    ForumPasswordLoginRequest request,
  ) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'request_cancelled',
          diagnosticMessage: 'request_cancelled',
        ),
      );
    }
    final security = request.securityAnswer;
    final result = await _repository.login(
      username: request.username,
      password: request.password,
      questionId: security?.questionId ?? '0',
      answer: security?.answer ?? '',
    );
    return switch (result) {
      ApiSuccess<SessionInfo>(:final data) when data.isLoggedIn =>
        DataCommandApplied(
          ForumLoginReceipt(
            ForumSessionIdentity(userId: data.uid, username: data.username),
          ),
        ),
      ApiSuccess<SessionInfo>() => const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unauthenticated,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'login_session_not_applied',
          diagnosticMessage: 'login_session_not_applied',
        ),
      ),
      ApiFailure<SessionInfo>(:final error) => DataCommandRejected(
        _commandFailure(error),
      ),
    };
  }
}

final class _TestLogoutCommand implements ForumLogoutCommand {
  const _TestLogoutCommand(this._repository);
  final AuthRepository _repository;

  @override
  Future<DataCommandResult<ForumLogoutReceipt>> execute([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]) async {
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'request_cancelled',
          diagnosticMessage: 'request_cancelled',
        ),
      );
    }
    try {
      await _repository.logout();
      return const DataCommandApplied(ForumLogoutReceipt());
    } on Object catch (error) {
      return DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'test_logout_failed',
          diagnosticMessage: error.runtimeType.toString(),
        ),
      );
    }
  }
}

DataCommandFailure _commandFailure(ApiError error) => DataCommandFailure(
  kind: switch (error.type) {
    ApiErrorType.network => DataCommandFailureKind.network,
    ApiErrorType.timeout => DataCommandFailureKind.timeout,
    ApiErrorType.unauthorized => DataCommandFailureKind.unauthenticated,
    ApiErrorType.server => DataCommandFailureKind.server,
    ApiErrorType.parse => DataCommandFailureKind.parse,
    ApiErrorType.business => DataCommandFailureKind.permissionDenied,
    ApiErrorType.unknown => DataCommandFailureKind.unknown,
  },
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: error.code ?? error.type.name,
  statusCode: error.statusCode,
  diagnosticMessage: error.code ?? error.type.name,
);
