import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_poll_vote_command.dart';
import '../network/forum_request.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import 'discuz_api_client.dart';

/// Experimental Discuz API v2 adapter for thread poll submission.
final class DiscuzThreadPollVoteCommand implements ThreadPollVoteCommand {
  /// Creates a command on the shared API and formhash boundary.
  const DiscuzThreadPollVoteCommand({
    required DiscuzApiClient api,
    required ForumClientConfig config,
    required ForumFormhashProvider formhash,
  }) : this._(api, config, formhash);

  const DiscuzThreadPollVoteCommand._(this._api, this._config, this._formhash);

  final DiscuzApiClient _api;
  final ForumClientConfig _config;
  final ForumFormhashProvider _formhash;

  @override
  ThreadPollVoteCapabilities get capabilities => _capabilities;

  @override
  Future<DataCommandResult<ThreadPollVoteReceipt>> execute(
    ThreadPollVoteSubmission submission,
  ) async {
    final fid = submission.fid.trim();
    final tid = submission.tid.trim();
    final optionIds = submission.optionIds;
    if (!_positive(fid) || !_positive(tid)) {
      return _notSent('thread_poll_vote_identity_invalid');
    }
    if (optionIds.isEmpty || !_validOrderedOptions(optionIds)) {
      return _notSent('thread_poll_vote_options_invalid');
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }

    final formhashResult = await _formhash.loadFormhash(
      preferProfile: true,
      cancellation: submission.cancellation,
    );
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent(_formhashFailure(failure));
    }
    final formhash = (formhashResult as ForumFormhashSuccess).value.trim();
    if (formhash.isEmpty) {
      return _notSent(
        'formhash_unavailable',
        kind: DataCommandFailureKind.staleFormhash,
        retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }

    final response = await _api.postFormFields(
      module: 'pollvote',
      queryParameters: <String, Object?>{
        'version': '2',
        'pollsubmit': 'yes',
        'fid': fid,
        'tid': tid,
      },
      form: ForumFormFields(<MapEntry<String, String>>[
        MapEntry<String, String>('formhash', formhash),
        for (final optionId in optionIds)
          MapEntry<String, String>('pollanswers[]', optionId),
      ]),
      treatMessageAsBusinessError: false,
      referer: _config.siteOrigin.replace(
        path: '/forum.php',
        queryParameters: <String, String>{
          'mod': 'viewthread',
          'tid': tid,
          'mobile': '2',
        },
      ),
      cancellation: submission.cancellation,
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(_transportFailure(failure));
    }

    final envelope =
        (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response
            .body;
    if (envelope.version != '2') {
      return _unknown('thread_poll_vote_response_version_invalid');
    }
    final normalized = _normalizeMessageCode(
      envelope.message?['messageval']?.toString() ?? '',
    );
    if (normalized.base == 'thread_poll_succeed' && !normalized.loginRequired) {
      return DataCommandApplied(
        ThreadPollVoteReceipt(
          fid: fid,
          tid: tid,
          optionIds: List<String>.unmodifiable(optionIds),
        ),
      );
    }
    if (_rejectionCodes.contains(normalized.base)) {
      return DataCommandRejected(_rejectionFailure(normalized));
    }
    return _unknown(
      normalized.base.isEmpty
          ? 'thread_poll_vote_success_unproved'
          : 'thread_poll_vote_response_unrecognized',
    );
  }
}

final _capabilities = ThreadPollVoteCapabilities(
  values: DataCapabilitySet.supported(ThreadPollVoteCapability.values),
);

const _rejectionCodes = <String>{
  'group_nopermission',
  'thread_poll_closed',
  'thread_poll_invalid',
  'poll_not_found',
  'poll_overdue',
  'poll_choose_most',
  'thread_poll_voted',
  'parameters_error',
  'submit_invalid',
};

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);

bool _validOrderedOptions(List<String> values) {
  final seen = <String>{};
  return values.every(
    (value) => value.trim() == value && _positive(value) && seen.add(value),
  );
}

DataCommandNotSent<ThreadPollVoteReceipt> _notSent(
  String code, {
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
  DataCommandRetryPolicy retryPolicy = DataCommandRetryPolicy.afterInputChange,
}) => DataCommandNotSent(
  DataCommandFailure(
    kind: kind,
    retryPolicy: retryPolicy,
    code: code,
    diagnosticMessage: code,
  ),
);

DataCommandNotSent<ThreadPollVoteReceipt> _cancelledNotSent() =>
    const DataCommandNotSent(
      DataCommandFailure(
        kind: DataCommandFailureKind.cancelled,
        retryPolicy: DataCommandRetryPolicy.never,
        code: 'request_cancelled',
        diagnosticMessage: 'request_cancelled',
      ),
    );

DataCommandOutcomeUnknown<ThreadPollVoteReceipt> _unknown(String code) =>
    DataCommandOutcomeUnknown(
      DataCommandFailure(
        kind: DataCommandFailureKind.parse,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        code: code,
        diagnosticMessage: code,
      ),
    );

DataCommandFailure _formhashFailure(ForumTransportFailure failure) =>
    DataCommandFailure(
      kind: failure.kind == ForumTransportFailureKind.cancelled
          ? DataCommandFailureKind.cancelled
          : DataCommandFailureKind.staleFormhash,
      retryPolicy: failure.kind == ForumTransportFailureKind.cancelled
          ? DataCommandRetryPolicy.never
          : DataCommandRetryPolicy.afterSessionRefresh,
      code: failure.code,
      statusCode: failure.statusCode,
      diagnosticMessage: failure.code,
    );

DataCommandFailure _transportFailure(
  ForumTransportFailure failure,
) => DataCommandFailure(
  kind: failure.statusCode == 405
      ? DataCommandFailureKind.securityChallenge
      : switch (failure.kind) {
          ForumTransportFailureKind.network => DataCommandFailureKind.network,
          ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
          ForumTransportFailureKind.unauthorized =>
            DataCommandFailureKind.unauthenticated,
          ForumTransportFailureKind.server => DataCommandFailureKind.server,
          ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
          ForumTransportFailureKind.business => DataCommandFailureKind.unknown,
          ForumTransportFailureKind.cancelled =>
            DataCommandFailureKind.cancelled,
          ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
        },
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

DataCommandFailure _rejectionFailure(({String base, bool loginRequired}) code) {
  final kind = switch (code.base) {
    _ when code.loginRequired => DataCommandFailureKind.unauthenticated,
    'group_nopermission' => DataCommandFailureKind.permissionDenied,
    'submit_invalid' => DataCommandFailureKind.staleFormhash,
    _ => DataCommandFailureKind.validation,
  };
  return DataCommandFailure(
    kind: kind,
    retryPolicy: switch (kind) {
      DataCommandFailureKind.unauthenticated ||
      DataCommandFailureKind.staleFormhash =>
        DataCommandRetryPolicy.afterSessionRefresh,
      DataCommandFailureKind.validation =>
        code.base == 'poll_choose_most'
            ? DataCommandRetryPolicy.afterInputChange
            : DataCommandRetryPolicy.explicitOnly,
      _ => DataCommandRetryPolicy.explicitOnly,
    },
    code: code.base,
    diagnosticMessage: code.base,
  );
}

({String base, bool loginRequired}) _normalizeMessageCode(String value) {
  var normalized = value.trim().toLowerCase();
  final loginSeparator = normalized.indexOf('//');
  final loginRequired =
      loginSeparator >= 0 &&
      normalized.substring(loginSeparator + 2).split('/').contains('1');
  if (loginSeparator >= 0) {
    normalized = normalized.substring(0, loginSeparator);
  }
  if (normalized.startsWith('mobile:')) {
    normalized = normalized.substring('mobile:'.length);
  }
  return (base: normalized, loginRequired: loginRequired);
}
