import '../network/forum_request.dart';
import 'data_command_contract.dart';

/// Stable authenticated identity proved by the forum.
final class ForumSessionIdentity {
  /// Creates a source-neutral authenticated identity.
  const ForumSessionIdentity({required this.userId, required this.username});

  /// Stable non-zero forum user ID.
  final String userId;

  /// Display name, which may be empty when the source omits it.
  final String username;
}

/// Result of resolving the current Cookie-backed forum session.
sealed class ForumSessionResult {
  const ForumSessionResult();
}

/// The source conclusively proved an authenticated user.
final class ForumSessionAuthenticated extends ForumSessionResult {
  /// Creates an authenticated result.
  const ForumSessionAuthenticated(this.identity);

  /// Proved user identity.
  final ForumSessionIdentity identity;
}

/// The source conclusively proved an anonymous session.
final class ForumSessionAnonymous extends ForumSessionResult {
  /// Creates an anonymous result.
  const ForumSessionAnonymous();
}

/// The source could not safely decide whether the session is authenticated.
final class ForumSessionInconclusive extends ForumSessionResult {
  /// Creates an inconclusive result with safe diagnostics.
  const ForumSessionInconclusive(this.failure);

  /// Failure that prevented an authoritative decision.
  final DataCommandFailure failure;
}

/// Request for an authoritative current-session resolution.
final class ForumSessionRequest {
  /// Creates a session resolution request.
  const ForumSessionRequest({this.cancellation});

  /// Optional cancellation signal owned by the caller.
  final ForumRequestCancellation? cancellation;
}

/// Source-neutral current-session contract.
abstract interface class ForumSessionRepository {
  /// Resolves the reference using the configured forum boundary.
  Future<ForumSessionResult> resolve([
    ForumSessionRequest request = const ForumSessionRequest(),
  ]);
}

/// Optional Discuz security-question input for password login.
final class ForumLoginSecurityAnswer {
  /// Creates a transient security-question answer.
  const ForumLoginSecurityAnswer({required this.questionId, this.answer = ''});

  /// Server-defined security question identifier.
  final String questionId;

  /// User-provided answer; never persisted or included in diagnostics.
  final String answer;
}

/// Transient credentials submitted to a password-login command.
final class ForumPasswordLoginRequest {
  /// Creates a login request. Credentials remain owned by this call only.
  const ForumPasswordLoginRequest({
    required this.username,
    required this.password,
    this.securityAnswer,
    this.cancellation,
  });

  /// User-entered login name.
  final String username;

  /// User-entered password. Implementations must never persist or log it.
  final String password;

  /// Optional security-question response.
  final ForumLoginSecurityAnswer? securityAnswer;

  /// Optional cancellation signal owned by the caller.
  final ForumRequestCancellation? cancellation;
}

/// Receipt returned only after profile verification proves login.
final class ForumLoginReceipt {
  /// Creates a confirmed login receipt.
  const ForumLoginReceipt(this.session);

  /// Authenticated identity proved after the login request.
  final ForumSessionIdentity session;
}

/// Source-neutral password-login command.
abstract interface class ForumPasswordLoginCommand {
  /// Submits credentials and confirms the resulting session.
  Future<DataCommandResult<ForumLoginReceipt>> execute(
    ForumPasswordLoginRequest request,
  );
}

/// Request for an explicit forum logout.
final class ForumLogoutRequest {
  /// Creates a logout request.
  const ForumLogoutRequest({this.cancellation});

  /// Optional cancellation signal owned by the caller.
  final ForumRequestCancellation? cancellation;
}

/// Receipt returned only after logout is explicitly confirmed.
final class ForumLogoutReceipt {
  /// Creates a confirmed logout receipt.
  const ForumLogoutReceipt();
}

/// Source-neutral logout command.
abstract interface class ForumLogoutCommand {
  /// Logs out through the configured source without fallback protocols.
  Future<DataCommandResult<ForumLogoutReceipt>> execute([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]);
}
