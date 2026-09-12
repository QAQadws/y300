import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'discuz_blog_access.dart';
import 'discuz_blog_command_response.dart';

/// Shared account and response boundary for journal and comment mutations.
/// This decorates the existing Host transport; it owns no cookies or client.
final class DiscuzBlogMutationSession {
  /// Creates the boundary from existing composition-root dependencies.
  const DiscuzBlogMutationSession({
    required this.config,
    required this.network,
    required this.profiles,
    required this.sessions,
  });

  /// Site configuration.
  final ForumClientConfig config;

  /// Shared transport.
  final ForumClientNetwork network;

  /// Shared request profiles.
  final ForumRequestProfileResolver profiles;

  /// Shared session projection.
  final ForumSessionStore? sessions;

  /// Whether the requested actor is still signed in.
  bool currentActor(String id) {
    final session = sessions?.readCurrent();
    return session != null && session.isLoggedIn && session.userId == id;
  }

  /// Exact managed authority, without credentials or HTTPS downgrades.
  bool sameSite(Uri uri) =>
      uri.scheme == config.siteOrigin.scheme &&
      uri.host == config.siteOrigin.host &&
      uri.port == config.siteOrigin.port &&
      uri.userInfo.isEmpty;

  /// Reads a form and verifies both local and server-reported actor identity.
  Future<DataReadResult<String, Object?>> read(
    Uri uri, {
    required String actor,
    required Uri referer,
    required String operation,
    ForumRequestProfileKind profile = ForumRequestProfileKind.mobileHtml,
    ForumRequestCancellation? cancellation,
  }) async {
    if ((cancellation?.isCancelled ?? false) || !currentActor(actor)) {
      return _readFailure(
        'blog_operation_interrupted',
        DataReadFailureKind.cancelled,
      );
    }
    ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: uri,
          context: ForumRequestContext(
            operation: operation,
            module: 'blog',
            pageKind: 'blog.form',
            silent: true,
          ),
          headers: profiles.resolve(profile, referer: referer).headers,
          cancellation: cancellation,
        ),
      );
    } catch (_) {
      return _readFailure('blog_transport_failed', DataReadFailureKind.network);
    }
    if ((cancellation?.isCancelled ?? false) || !currentActor(actor)) {
      return _readFailure(
        'blog_operation_interrupted',
        DataReadFailureKind.cancelled,
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _readFailure(
        'blog_transport_failed',
        toReadFailureKind(failure.kind),
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        !sameSite(response.uri) ||
        response.body is! String) {
      return _readFailure('blog_response_invalid');
    }
    final source = response.body as String;
    final access = DiscuzBlogAccess.failure<String, Object?>(source);
    if (access != null) return access;
    // Normal mobile and desktop GETs expose this identity in header.htm.
    final actors = html
        .parse(source)
        .querySelectorAll('script')
        .expand(
          (script) => RegExp(
            r'''(?:^|[,;])\s*discuz_uid\s*=\s*['"](\d+)['"]''',
          ).allMatches(script.text),
        )
        .map((match) => match.group(1))
        .toSet();
    if (actors.length != 1 || actors.single != actor) {
      return _readFailure(
        'blog_account_unverified',
        DataReadFailureKind.unauthorized,
      );
    }
    return DataReadSuccess(
      data: source,
      capabilities: null,
      metadata: const DataReadMetadata.network(),
    );
  }

  /// Sends once and extracts an explicit callback; the caller must additionally
  /// prove its own receipt identities before exposing an applied result.
  Future<DataCommandResult<DiscuzBlogCommandResponse>> submit(
    Uri uri, {
    required String actor,
    required Uri referer,
    required String operation,
    required String handleKey,
    required Map<String, String> fields,
    ForumRequestProfileKind profile = ForumRequestProfileKind.mobileHtml,
    ForumRequestCancellation? cancellation,
    bool multipart = false,
  }) async {
    if ((cancellation?.isCancelled ?? false) || !currentActor(actor)) {
      return DataCommandNotSent(
        _failure(
          'blog_operation_interrupted',
          DataCommandFailureKind.cancelled,
          DataCommandRetryPolicy.explicitOnly,
        ),
      );
    }
    final body = {
      ...fields,
      'referer': referer.toString(),
      'handlekey': handleKey,
    };
    ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'inajax': '1',
              'handlekey': handleKey,
            },
          ),
          context: ForumRequestContext(
            operation: operation,
            module: 'blog',
            pageKind: 'blog.form',
            silent: true,
          ),
          headers: profiles.resolve(profile, referer: referer).headers,
          body: multipart ? ForumMultipartFields(body.entries) : body,
          cancellation: cancellation,
          followRedirects: false,
        ),
      );
    } catch (_) {
      return _unknown('blog_transport_failed', DataCommandFailureKind.network);
    }
    if ((cancellation?.isCancelled ?? false) || !currentActor(actor)) {
      return _unknown(
        'blog_operation_interrupted',
        DataCommandFailureKind.cancelled,
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _unknown(
        'blog_transport_failed',
        failure.kind == ForumTransportFailureKind.timeout
            ? DataCommandFailureKind.timeout
            : DataCommandFailureKind.network,
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        !sameSite(response.uri) ||
        response.body is! String) {
      return _unknown('blog_response_invalid');
    }
    final outcome = DiscuzBlogCommandResponse.parse(
      response.body as String,
      handleKey,
    );
    if (outcome == null) return _unknown('blog_response_unproved');
    if (!outcome.applied) {
      return DataCommandRejected(
        _failure(
          'blog_operation_rejected',
          DataCommandFailureKind.validation,
          DataCommandRetryPolicy.afterInputChange,
        ),
      );
    }
    return DataCommandApplied(outcome);
  }
}

/// Preserves a non-applied result while changing the operation's receipt type.
DataCommandResult<T> retypeBlogCommandFailure<T>(
  DataCommandResult<Object?> result,
) => switch (result) {
  DataCommandNotSent(:final failure) => DataCommandNotSent(failure),
  DataCommandRejected(:final failure) => DataCommandRejected(failure),
  DataCommandOutcomeUnknown(:final failure) => DataCommandOutcomeUnknown(
    failure,
  ),
  DataCommandUnsupported(:final failure) => DataCommandUnsupported(failure),
  DataCommandApplied() => throw StateError(
    'Applied result needs operation-specific verification',
  ),
};

DataReadFailure<T, C> _readFailure<T, C>(
  String code, [
  DataReadFailureKind kind = DataReadFailureKind.parse,
]) => DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
DataCommandFailure _failure(
  String code,
  DataCommandFailureKind kind,
  DataCommandRetryPolicy retry,
) => DataCommandFailure(
  kind: kind,
  retryPolicy: retry,
  code: code,
  diagnosticMessage: code,
);
DataCommandOutcomeUnknown<T> _unknown<T>(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.parse,
]) => DataCommandOutcomeUnknown(
  _failure(code, kind, DataCommandRetryPolicy.never),
);
