import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_daily_sign_in.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_daily_sign_in_command_evidence.dart';
import 'discuz_daily_sign_in_page_parser.dart';

/// Network-only mobile sign-in source shared by the read and command ports.
/// No document or snapshot cache is used.
final class DiscuzDailySignInAdapter {
  /// Creates an adapter over the one shared forum transport.
  DiscuzDailySignInAdapter({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    this.parser = const DiscuzDailySignInPageParser(),
  }) : _pageUri = config.siteOrigin.replace(
         path: '/plugin.php',
         queryParameters: const {'id': 'zqlj_sign', 'mobile': '2'},
       );

  final Uri _pageUri;

  /// Shared transport owned by the host.
  final ForumClientNetwork network;

  /// Mobile HTML browser identity used by this source.
  final ForumRequestProfileResolver requestProfiles;

  /// Read-only parser for the current page.
  final DiscuzDailySignInPageParser parser;

  /// Source-declared status and optional statistics support.
  ForumDailySignInSourceCapabilities get capabilities =>
      ForumDailySignInSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      );

  /// Command support; positive attribution awaits observed response evidence.
  ForumDailySignInCommandCapabilities get commandCapabilities =>
      ForumDailySignInCommandCapabilities(
        values: DataCapabilitySet.from(
          supported: const [ForumDailySignInCommandCapability.signIn],
          unsupported: const [
            ForumDailySignInCommandCapability.readBackConfirmation,
          ],
        ),
      );

  /// Reads the current user's status directly from the forum.
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query) async {
    final result = await _readPage(query.userId, query.cancellation);
    if (result
        case DataReadFailure<
              DiscuzDailySignInPage,
              ForumDailySignInReadCapabilities
            >
            failure) {
      return failure.retype();
    }
    final success =
        result
            as DataReadSuccess<
              DiscuzDailySignInPage,
              ForumDailySignInReadCapabilities
            >;
    return DataReadSuccess(
      data: success.data.snapshot,
      capabilities: success.capabilities,
      metadata: success.metadata,
    );
  }

  /// Prepares a fresh opaque link and submits it at most once.
  Future<DataCommandResult<ForumDailySignInReceipt>> execute(
    ForumDailySignInRequest request,
  ) async {
    final prepared = await _readPage(request.userId, request.cancellation);
    if (prepared
        case DataReadFailure<
              DiscuzDailySignInPage,
              ForumDailySignInReadCapabilities
            >
            failure) {
      return DataCommandNotSent(_notSentFailure(failure));
    }
    final page =
        (prepared
                as DataReadSuccess<
                  DiscuzDailySignInPage,
                  ForumDailySignInReadCapabilities
                >)
            .data;
    if (request.expectedForumDay != null &&
        request.expectedForumDay != page.snapshot.forumDay) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_forum_day_changed',
          diagnosticMessage: 'daily_sign_in_forum_day_changed',
        ),
      );
    }
    if (page.snapshot.status == ForumDailySignInStatus.signed) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.validation,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'daily_sign_in_already_signed',
          diagnosticMessage: 'daily_sign_in_already_signed',
        ),
      );
    }
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_cancelled_before_send',
          diagnosticMessage: 'daily_sign_in_cancelled_before_send',
        ),
      );
    }

    // Only the fresh, validated page may supply this opaque one-use action.
    final signUri = page.signUri;
    if (signUri == null) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_action_missing',
          diagnosticMessage: 'daily_sign_in_action_missing',
        ),
      );
    }
    if (request.beforeSend case final beforeSend?) {
      ForumDailySignInSendAuthorization authorization;
      try {
        authorization = await beforeSend(
          ForumDailySignInPreparedAttempt(
            userId: page.snapshot.userId,
            forumDay: page.snapshot.forumDay,
          ),
        );
      } catch (_) {
        authorization = ForumDailySignInSendAuthorization.unavailable;
      }
      switch (authorization) {
        case ForumDailySignInSendAuthorization.allow:
          break;
        case ForumDailySignInSendAuthorization.suppress:
          return const DataCommandNotSent(
            DataCommandFailure(
              kind: DataCommandFailureKind.validation,
              retryPolicy: DataCommandRetryPolicy.explicitOnly,
              code: 'daily_sign_in_send_suppressed',
              diagnosticMessage: 'daily_sign_in_send_suppressed',
            ),
          );
        case ForumDailySignInSendAuthorization.unavailable:
          return const DataCommandNotSent(
            DataCommandFailure(
              kind: DataCommandFailureKind.unknown,
              retryPolicy: DataCommandRetryPolicy.explicitOnly,
              code: 'daily_sign_in_send_gate_failed',
              diagnosticMessage: 'daily_sign_in_send_gate_failed',
            ),
          );
      }
    }
    if (request.cancellation?.isCancelled ?? false) {
      return const DataCommandNotSent(
        DataCommandFailure(
          kind: DataCommandFailureKind.cancelled,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_cancelled_before_send',
          diagnosticMessage: 'daily_sign_in_cancelled_before_send',
        ),
      );
    }
    ForumTransportResult<ForumResponse<Object?>> sent;
    try {
      sent = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: signUri,
          context: const ForumRequestContext(
            operation: 'profile.daily_sign_in.submit',
            module: 'profile',
            pageKind: 'daily_sign_in.submit',
            silent: true,
          ),
          headers: requestProfiles
              .resolve(ForumRequestProfileKind.mobileHtml, referer: _pageUri)
              .headers,
          followRedirects: false,
          allowWafReplay: false,
          cancellation: request.cancellation,
        ),
      );
    } catch (_) {
      return const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_transport_unconfirmed',
          diagnosticMessage: 'daily_sign_in_transport_unconfirmed',
        ),
      );
    }

    final observation = _textObservation(sent);
    final unknown = unconfirmedDailySignInPostSend(observation);
    if (!(request.cancellation?.isCancelled ?? false)) {
      // A positive read proves today's state, but cannot attribute the effect
      // to this command until a real response has calibrated submit evidence.
      await _readPage(request.userId, request.cancellation);
    }
    return unknown;
  }

  Future<
    DataReadResult<DiscuzDailySignInPage, ForumDailySignInReadCapabilities>
  >
  _readPage(String userId, ForumRequestCancellation? cancellation) async {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(userId)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'daily_sign_in_user_invalid',
        diagnosticMessage: 'daily_sign_in_user_invalid',
      );
    }
    if (cancellation?.isCancelled ?? false) {
      return const DataReadFailure(
        kind: DataReadFailureKind.cancelled,
        code: 'daily_sign_in_read_cancelled',
        diagnosticMessage: 'daily_sign_in_read_cancelled',
      );
    }
    ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: _pageUri,
          context: const ForumRequestContext(
            operation: 'profile.daily_sign_in.read',
            module: 'profile',
            pageKind: 'daily_sign_in',
          ),
          headers: requestProfiles
              .resolve(ForumRequestProfileKind.mobileHtml)
              .headers,
          followRedirects: false,
          cancellation: cancellation,
        ),
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        code: 'daily_sign_in_read_unknown',
        diagnosticMessage: 'daily_sign_in_read_unknown',
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return DataReadFailure(
        kind: failure.statusCode == 404
            ? DataReadFailureKind.unsupported
            : failure.statusCode == 401 || failure.statusCode == 403
            ? DataReadFailureKind.unauthorized
            : toReadFailureKind(failure.kind),
        code: 'daily_sign_in_transport_failed',
        statusCode: failure.statusCode,
        diagnosticMessage: 'daily_sign_in_transport_failed',
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 || response.body is! String) {
      return DataReadFailure(
        kind: response.statusCode == 401 || response.statusCode == 403
            ? DataReadFailureKind.unauthorized
            : response.statusCode == 404
            ? DataReadFailureKind.unsupported
            : DataReadFailureKind.parse,
        code: 'daily_sign_in_response_invalid',
        statusCode: response.statusCode,
        diagnosticMessage: 'daily_sign_in_response_invalid',
      );
    }
    try {
      final page = parser.parse(
        response.body as String,
        requestedUri: _pageUri,
        sourceUri: response.uri,
        expectedUserId: userId,
      );
      return DataReadSuccess(
        data: page,
        capabilities: ForumDailySignInReadCapabilities(
          values: DataCapabilitySet.from(
            supported: [
              ForumDailySignInReadCapability.todayStatus,
              if (page.snapshot.statistics != null)
                ForumDailySignInReadCapability.orderedStatistics,
            ],
            unsupported: [
              if (page.snapshot.statistics == null)
                ForumDailySignInReadCapability.orderedStatistics,
            ],
          ),
        ),
        metadata: const DataReadMetadata.network(),
      );
    } on DiscuzDailySignInParseFailure catch (failure) {
      return DataReadFailure(
        kind: failure.kind,
        code: failure.code,
        diagnosticMessage: failure.code,
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'daily_sign_in_parse_failed',
        diagnosticMessage: 'daily_sign_in_parse_failed',
      );
    }
  }

  DataCommandFailure _notSentFailure(
    DataReadFailure<DiscuzDailySignInPage, ForumDailySignInReadCapabilities>
    read,
  ) {
    final kind = switch (read.kind) {
      DataReadFailureKind.unauthorized =>
        DataCommandFailureKind.unauthenticated,
      DataReadFailureKind.cancelled => DataCommandFailureKind.cancelled,
      DataReadFailureKind.timeout => DataCommandFailureKind.timeout,
      DataReadFailureKind.network => DataCommandFailureKind.network,
      DataReadFailureKind.server => DataCommandFailureKind.server,
      DataReadFailureKind.parse => DataCommandFailureKind.parse,
      DataReadFailureKind.unsupported => DataCommandFailureKind.unsupported,
      DataReadFailureKind.business => DataCommandFailureKind.validation,
      DataReadFailureKind.unknown => DataCommandFailureKind.unknown,
    };
    return DataCommandFailure(
      kind: kind,
      retryPolicy: kind == DataCommandFailureKind.unsupported
          ? DataCommandRetryPolicy.never
          : DataCommandRetryPolicy.explicitOnly,
      code: read.code,
      statusCode: read.statusCode,
      diagnosticMessage: read.diagnosticMessage,
    );
  }

  ForumTransportResult<ForumResponse<String>> _textObservation(
    ForumTransportResult<ForumResponse<Object?>> result,
  ) => switch (result) {
    ForumTransportError<ForumResponse<Object?>>(:final failure) =>
      ForumTransportError(failure),
    ForumTransportSuccess<ForumResponse<Object?>>(:final response) =>
      ForumTransportSuccess(
        ForumResponse(
          uri: response.uri,
          statusCode: response.statusCode,
          headers: const {},
          body: response.body is String ? response.body as String : '',
        ),
      ),
  };
}

/// Read contract backed by a shared sign-in adapter.
final class DiscuzDailySignInRepository implements ForumDailySignInRepository {
  /// Creates the read port.
  const DiscuzDailySignInRepository(this._adapter);

  final DiscuzDailySignInAdapter _adapter;

  @override
  ForumDailySignInSourceCapabilities get capabilities => _adapter.capabilities;

  @override
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query) => _adapter.load(query);
}

/// Command contract backed by a shared sign-in adapter.
final class DiscuzDailySignInCommandAdapter implements ForumDailySignInCommand {
  /// Creates the command port.
  const DiscuzDailySignInCommandAdapter(this._adapter);

  final DiscuzDailySignInAdapter _adapter;

  @override
  ForumDailySignInCommandCapabilities get capabilities =>
      _adapter.commandCapabilities;

  @override
  Future<DataCommandResult<ForumDailySignInReceipt>> execute(
    ForumDailySignInRequest request,
  ) => _adapter.execute(request);
}
