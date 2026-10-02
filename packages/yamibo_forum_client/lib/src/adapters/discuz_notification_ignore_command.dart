import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/notification_ignore_command.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';

/// Discuz's type/author notification filter, separate from the PM blacklist.
final class DiscuzNotificationIgnoreCommand
    implements ForumNotificationIgnoreCommand {
  /// Uses the existing Host session, transport and formhash provider.
  const DiscuzNotificationIgnoreCommand({
    required this.config,
    required this.network,
    required this.profiles,
    required this.formhash,
  });

  /// Source origin used to build the fixed action and safe return URL.
  final ForumClientConfig config;

  /// Shared authenticated transport.
  final ForumClientNetwork network;

  /// Host-supplied request identities.
  final ForumRequestProfileResolver profiles;

  /// Shared current-session formhash resolver.
  final ForumFormhashProvider formhash;

  @override
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> execute(
    ForumNotificationIgnoreSubmission submission,
  ) async {
    final author = submission.scope == ForumNotificationIgnoreScope.allAuthors
        ? '0'
        : submission.authorId;
    if (!_positive(submission.notificationId) ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(submission.type) ||
        (submission.authorId != '0' && !_positive(submission.authorId)) ||
        (author == '0' &&
            submission.scope == ForumNotificationIgnoreScope.author)) {
      return DataCommandNotSent(
        _failure(
          'notification_ignore_input_invalid',
          DataCommandFailureKind.validation,
        ),
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    final ForumFormhashResult hashResult;
    try {
      hashResult = await formhash.loadFormhash(
        cancellation: submission.cancellation,
      );
    } on Object {
      return DataCommandNotSent(
        _failure(
          'notification_ignore_preparation_failed',
          DataCommandFailureKind.unknown,
        ),
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (hashResult case ForumFormhashError(:final failure)) {
      return DataCommandNotSent(
        _failure(
          'notification_ignore_session_unavailable',
          failure.kind == ForumTransportFailureKind.unauthorized
              ? DataCommandFailureKind.unauthenticated
              : DataCommandFailureKind.staleFormhash,
        ),
      );
    }
    final hash = (hashResult as ForumFormhashSuccess).value.trim();
    if (hash.isEmpty) {
      return DataCommandNotSent(
        _failure('formhash_unavailable', DataCommandFailureKind.staleFormhash),
      );
    }

    final referer = config.siteOrigin.resolve('home.php?mod=space&do=notice');
    final uri = config.siteOrigin
        .resolve('home.php')
        .replace(
          queryParameters: {
            'mod': 'spacecp',
            'ac': 'common',
            'op': 'ignore',
            'type': submission.type,
            'id': submission.notificationId,
            'inajax': '1',
            'handlekey': _handle,
          },
        );
    final ForumTransportResult<ForumResponse<Object?>> response;
    try {
      // The mobile template offers the same action but omits the callback.
      // A desktop AJAX response provides the exact mutated id/type/uid tuple.
      response = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: uri,
          context: const ForumRequestContext(
            operation: 'notification.ignore',
            pageKind: 'profile.notifications',
          ),
          headers: {
            ...profiles
                .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
                .headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'formhash': hash,
            'ignoresubmit': 'true',
            'authorid': author,
            'referer': referer.toString(),
            'handlekey': _handle,
          },
          followRedirects: false,
          cancellation: submission.cancellation,
        ),
      );
    } on Object {
      return _unknown();
    }
    if (response is ForumTransportError<ForumResponse<Object?>>) {
      return _unknown();
    }
    final value =
        (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (value.statusCode != 200 || value.uri != uri || value.body is! String) {
      return _unknown();
    }
    final outcome = _callbackOutcome(
      value.body as String,
      referer,
      submission,
      author,
    );
    return switch (outcome) {
      _Outcome.applied => DataCommandApplied(
        ForumNotificationIgnoreReceipt(
          notificationId: submission.notificationId,
          type: submission.type,
          authorId: author,
        ),
      ),
      _Outcome.rejected => DataCommandRejected(
        _failure(
          'notification_ignore_rejected',
          DataCommandFailureKind.validation,
        ),
      ),
      _Outcome.unknown => _unknown(),
    };
  }
}

const _handle = 'y300_notice_ignore';

enum _Outcome { applied, rejected, unknown }

_Outcome _callbackOutcome(
  String source,
  Uri referer,
  ForumNotificationIgnoreSubmission submission,
  String author,
) {
  final envelopes = RegExp(
    r'<!\[CDATA\[([\s\S]*?)\]\]>',
  ).allMatches(source).toList();
  if (envelopes.length > 1 ||
      (envelopes.isEmpty && source.contains('<![CDATA['))) {
    return _Outcome.unknown;
  }
  final payload = envelopes.isEmpty ? source : envelopes.single.group(1)!;
  final document = html.parse(payload);
  // Match actual script calls, not visible text, attributes or callback names
  // merely appearing inside the server's quoted human-readable message.
  const quoted = r'''(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''';
  final call = RegExp(
    '(?:^|[;{}])\\s*(succeedhandle_|errorhandle_)$_handle\\s*\\(\\s*($quoted)\\s*,\\s*($quoted|\\{[^{}]*\\})(?:\\s*,\\s*(\\{[^{}]*\\}))?\\s*\\)\\s*;',
    multiLine: true,
  );
  final calls = [
    for (final script in document.querySelectorAll('script'))
      ...call.allMatches(script.text),
  ];
  if (calls.length != 1) return _Outcome.unknown;
  final match = calls.single;
  if (match.group(1) == 'errorhandle_') return _Outcome.rejected;
  final forward = match.group(2)!;
  if (forward.substring(1, forward.length - 1) != referer.toString()) {
    return _Outcome.unknown;
  }
  final object = match.group(4);
  if (object == null) return _Outcome.unknown;
  final field = RegExp(
    r'''['"](id|type|uid)['"]\s*:\s*['"]([a-zA-Z0-9_.-]+)['"]''',
  );
  final fields = field.allMatches(object).toList();
  if (fields.length != 3 ||
      fields.map((item) => item.group(1)).toSet().length != 3 ||
      object
          .replaceAll(field, '')
          .replaceAll(RegExp(r'[{},\s]'), '')
          .isNotEmpty) {
    return _Outcome.unknown;
  }
  final values = {for (final item in fields) item.group(1)!: item.group(2)!};
  return values['id'] == submission.notificationId &&
          values['type'] == submission.type &&
          values['uid'] == author
      ? _Outcome.applied
      : _Outcome.unknown;
}

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);
DataCommandFailure _failure(String code, DataCommandFailureKind kind) =>
    DataCommandFailure(
      kind: kind,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: code,
      diagnosticMessage: code,
    );
DataCommandNotSent<ForumNotificationIgnoreReceipt> _cancelled() =>
    DataCommandNotSent(
      _failure('request_cancelled', DataCommandFailureKind.cancelled),
    );
DataCommandOutcomeUnknown<ForumNotificationIgnoreReceipt> _unknown() =>
    DataCommandOutcomeUnknown(
      _failure(
        'notification_ignore_success_unproved',
        DataCommandFailureKind.unknown,
      ),
    );
