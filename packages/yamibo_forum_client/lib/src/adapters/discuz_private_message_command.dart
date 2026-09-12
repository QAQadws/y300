import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/private_message_command.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import 'discuz_api_client.dart';

/// Discuz sendpm v1 implementation using the shared transport and formhash.
final class DiscuzPrivateMessageCommand implements ForumPrivateMessageCommand {
  /// Creates a command without introducing a private session or HTTP client.
  const DiscuzPrivateMessageCommand({
    required DiscuzApiClient api,
    required ForumClientConfig config,
    required ForumFormhashProvider formhash,
  }) : this._(api, config, formhash);

  const DiscuzPrivateMessageCommand._(this._api, this._config, this._formhash);

  final DiscuzApiClient _api;
  final ForumClientConfig _config;
  final ForumFormhashProvider _formhash;

  @override
  Future<DataCommandResult<ForumPrivateMessageReceipt>> execute(
    ForumPrivateMessageSubmission submission,
  ) async {
    final recipient = submission.recipient;
    if (!_validRecipient(recipient) || submission.message.trim().isEmpty) {
      return DataCommandNotSent(
        _failure(
          'private_message_input_invalid',
          DataCommandFailureKind.validation,
        ),
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (_config.apiOrigin == null) return const DataCommandUnsupported();

    final ForumFormhashResult formhashResult;
    try {
      formhashResult = await _formhash.loadFormhash(
        cancellation: submission.cancellation,
      );
    } on Object {
      return DataCommandNotSent(
        _failure(
          'private_message_preparation_failed',
          DataCommandFailureKind.unknown,
        ),
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (formhashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent(
        _failure(
          'private_message_session_unavailable',
          _transportKind(failure),
        ),
      );
    }
    final hash = (formhashResult as ForumFormhashSuccess).value.trim();
    if (hash.isEmpty) {
      return DataCommandNotSent(
        _failure('formhash_unavailable', DataCommandFailureKind.staleFormhash),
      );
    }

    final ForumTransportResult<ForumResponse<DiscuzApiEnvelope>> response;
    try {
      // v4 copies GET into POST. v1 accepts a real form body, keeping private
      // content and usernames out of URLs, redirects and URL diagnostics.
      response = await _api.postForm(
        module: 'sendpm',
        queryParameters: const {'version': '1'},
        form: {
          'formhash': hash,
          'pmsubmit': 'true',
          'message': submission.message,
          switch (recipient.kind) {
            ForumPrivateMessageRecipientKind.user => 'touid',
            ForumPrivateMessageRecipientKind.username => 'username',
            ForumPrivateMessageRecipientKind.group => 'plid',
          }: recipient.value,
          if (recipient.kind == ForumPrivateMessageRecipientKind.group)
            'pmid': recipient.replyMessageId!,
        },
        treatMessageAsBusinessError: false,
        referer: _config.siteOrigin.resolve(
          'home.php?mod=space&do=pm&mobile=2',
        ),
        cancellation: submission.cancellation,
      );
    } on Object {
      return _unknown('private_message_transport_failed');
    }
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: _transportKind(failure),
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'private_message_outcome_unknown',
          diagnosticMessage: 'private_message_outcome_unknown',
        ),
      );
    }
    final envelope =
        (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response
            .body;
    if (envelope.version != '1') {
      return _unknown('private_message_response_invalid');
    }
    var code = envelope.message?['messageval']?.toString().trim() ?? '';
    if (code.startsWith('mobile:')) code = code.substring(7);
    final base = code.split('//').first;
    final id = envelope.variables['pmid']?.toString() ?? '';
    // do_success is emitted only after sendpm returns a positive message ID.
    // Require both signals; arbitrary prose or a redirect never proves send.
    if (code == 'do_success' && _positive(id)) {
      return DataCommandApplied(
        ForumPrivateMessageReceipt(messageId: id, recipient: recipient),
      );
    }
    if (_rejections.contains(base) ||
        RegExp(r'^message_can_not_send_(?:[1-9]|1[0-6])$').hasMatch(base)) {
      final kind = switch (base) {
        'to_login' ||
        'login_before_enter_home' => DataCommandFailureKind.unauthenticated,
        'submit_invalid' => DataCommandFailureKind.staleFormhash,
        'no_privilege_sendpm' ||
        'is_blacklist' ||
        'message_can_not_send_onlyfriend' =>
          DataCommandFailureKind.permissionDenied,
        _ =>
          code.endsWith('//1')
              ? DataCommandFailureKind.unauthenticated
              : DataCommandFailureKind.validation,
      };
      return DataCommandRejected(_failure(base, kind));
    }
    return _unknown('private_message_success_unproved');
  }
}

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);

bool _validRecipient(
  ForumPrivateMessageRecipient recipient,
) => switch (recipient.kind) {
  ForumPrivateMessageRecipientKind.user => _positive(recipient.value),
  ForumPrivateMessageRecipientKind.group =>
    _positive(recipient.value) && _positive(recipient.replyMessageId ?? ''),
  // UCenter splits recipient names on commas; reject that implicit broadcast.
  ForumPrivateMessageRecipientKind.username =>
    recipient.value.trim().isNotEmpty &&
        !RegExp(r'[,\x00-\x1f\x7f]').hasMatch(recipient.value),
};

const _rejections = {
  'to_login',
  'login_before_enter_home',
  'submit_invalid',
  'parameters_error',
  'no_privilege_sendpm',
  'is_blacklist',
  'unable_to_send_air_news',
  'message_can_not_send_onlyfriend',
  'message_bad_touid',
  'message_bad_touser',
  'message_can_not_send_to_self',
  'message_can_not_send',
};

DataCommandNotSent<ForumPrivateMessageReceipt> _cancelled() =>
    DataCommandNotSent(
      _failure('request_cancelled', DataCommandFailureKind.cancelled),
    );

DataCommandOutcomeUnknown<ForumPrivateMessageReceipt> _unknown(String code) =>
    DataCommandOutcomeUnknown(_failure(code, DataCommandFailureKind.parse));

DataCommandFailure _failure(String code, DataCommandFailureKind kind) =>
    DataCommandFailure(
      kind: kind,
      retryPolicy:
          kind == DataCommandFailureKind.unauthenticated ||
              kind == DataCommandFailureKind.staleFormhash
          ? DataCommandRetryPolicy.afterSessionRefresh
          : DataCommandRetryPolicy.explicitOnly,
      code: code,
      diagnosticMessage: code,
    );

DataCommandFailureKind _transportKind(ForumTransportFailure failure) =>
    switch (failure.kind) {
      ForumTransportFailureKind.network => DataCommandFailureKind.network,
      ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
      ForumTransportFailureKind.unauthorized =>
        DataCommandFailureKind.unauthenticated,
      ForumTransportFailureKind.server =>
        failure.statusCode == 405
            ? DataCommandFailureKind.securityChallenge
            : DataCommandFailureKind.server,
      ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
      ForumTransportFailureKind.cancelled => DataCommandFailureKind.cancelled,
      ForumTransportFailureKind.business ||
      ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
    };
