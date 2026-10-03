import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/friend_feed.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'discuz_friend_feed_parser.dart';
import 'discuz_friend_literal_parser.dart';
import 'discuz_profile_html_parsers.dart';
import 'discuz_read_access_parser.dart';

/// Fresh-form, single-submission friend removal on the shared Host session.
final class DiscuzFriendRemovalCommand implements ForumFriendRemovalCommand {
  /// Creates the command without owning a second transport or session.
  const DiscuzFriendRemovalCommand({
    required this.config,
    required this.network,
    required this.profiles,
    required this.sessions,
  });

  /// Managed site and request configuration.
  final ForumClientConfig config;

  /// Shared Host transport.
  final ForumClientNetwork network;

  /// Host-supplied request profiles.
  final ForumRequestProfileResolver profiles;

  /// Shared authenticated account projection.
  final ForumSessionStore? sessions;

  @override
  Future<DataCommandResult<ForumFriendRemovalReceipt>> execute(
    ForumFriendRemovalSubmission submission,
  ) async {
    if (!discuzFriendPositiveId(submission.actorUserId) ||
        !discuzFriendPositiveId(submission.userId) ||
        submission.actorUserId == submission.userId) {
      return _notSent(
        'friend_removal_input_invalid',
        DataCommandFailureKind.validation,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (!_actor(submission.actorUserId)) {
      return _notSent(
        'friend_removal_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    final referer = config.siteOrigin
        .resolve('home.php')
        .replace(queryParameters: {'mod': 'space', 'do': 'friend'});
    final formUri = config.siteOrigin
        .resolve('home.php')
        .replace(
          queryParameters: {
            'mod': 'spacecp',
            'ac': 'friend',
            'op': 'ignore',
            'uid': submission.userId,
            'mobile': 'no',
          },
        );
    final ForumTransportResult<ForumResponse<Object?>> prepared;
    try {
      prepared = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: formUri,
          context: const ForumRequestContext(
            operation: 'friends.removal.prepare',
            module: 'profile',
            pageKind: 'profile.friends.form',
          ),
          headers: profiles
              .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
              .headers,
          followRedirects: false,
          cancellation: submission.cancellation,
        ),
      );
    } on Object {
      return _notSent(
        'friend_removal_preparation_failed',
        DataCommandFailureKind.network,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (!_actor(submission.actorUserId)) {
      return _notSent(
        'friend_removal_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (prepared is ForumTransportError<ForumResponse<Object?>>) {
      return _notSent(
        'friend_removal_preparation_failed',
        DataCommandFailureKind.network,
      );
    }
    final formResponse =
        (prepared as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (formResponse.statusCode == 401 || formResponse.statusCode == 403) {
      return _notSent(
        'friend_removal_login_required',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (formResponse.statusCode != 200 ||
        formResponse.uri != formUri ||
        formResponse.body is! String) {
      return _notSent(
        'friend_removal_form_unverified',
        DataCommandFailureKind.parse,
      );
    }
    final source = formResponse.body as String;
    if (DiscuzProfileAuthPageDetector.isLoginPage(source)) {
      return _notSent(
        'friend_removal_login_required',
        DataCommandFailureKind.unauthenticated,
      );
    }
    final String hash;
    try {
      hash = _formHash(html.parse(source), submission);
    } on FormatException {
      return _notSent(
        'friend_removal_form_unverified',
        DataCommandFailureKind.parse,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) return _cancelled();
    if (!_actor(submission.actorUserId)) {
      return _notSent(
        'friend_removal_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    final submitUri = formUri.replace(
      queryParameters: {
        ...formUri.queryParameters,
        'confirm': '1',
        'inajax': '1',
        'handlekey': _handle,
      },
    );
    final ForumTransportResult<ForumResponse<Object?>> sent;
    try {
      // This is the only mutation request. A failed transport or an ambiguous
      // callback remains unknown; the command never resends it automatically.
      sent = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: submitUri,
          context: const ForumRequestContext(
            operation: 'friends.removal.submit',
            module: 'profile',
            pageKind: 'profile.friends.form',
          ),
          headers: {
            ...profiles
                .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
                .headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'friendsubmit': 'true',
            'formhash': hash,
            'referer': referer.toString(),
            'from': '',
            'handlekey': _handle,
          },
          followRedirects: false,
          cancellation: submission.cancellation,
        ),
      );
    } on Object {
      return _unknown(
        'friend_removal_transport_failed',
        DataCommandFailureKind.network,
      );
    }
    if ((submission.cancellation?.isCancelled ?? false) ||
        !_actor(submission.actorUserId)) {
      return _unknown(
        'friend_removal_interrupted',
        DataCommandFailureKind.cancelled,
      );
    }
    if (sent is ForumTransportError<ForumResponse<Object?>>) {
      return _unknown(
        'friend_removal_transport_failed',
        DataCommandFailureKind.network,
      );
    }
    final response =
        (sent as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        response.uri != submitUri ||
        response.body is! String) {
      return _unknown('friend_removal_response_unverified');
    }
    final outcome = _outcome(response.body as String, submission.userId);
    return switch (outcome) {
      _Outcome.applied => DataCommandApplied(
        ForumFriendRemovalReceipt(
          actorUserId: submission.actorUserId,
          userId: submission.userId,
        ),
      ),
      _Outcome.rejected => DataCommandRejected(
        _failure(
          'friend_removal_rejected',
          DataCommandFailureKind.validation,
          DataCommandRetryPolicy.explicitOnly,
        ),
      ),
      _Outcome.unknown => _unknown('friend_removal_success_unproved'),
    };
  }

  bool _actor(String actor) {
    final current = sessions?.readCurrent();
    return current != null && current.isLoggedIn && current.userId == actor;
  }

  String _formHash(
    dom.Document document,
    ForumFriendRemovalSubmission submission,
  ) {
    if (!discuzFriendActorMatches(document, submission.actorUserId) ||
        document.querySelector('#messagetext, .jump_c, .alert_error') != null) {
      throw const FormatException('friend_removal_actor');
    }
    final forms = document.querySelectorAll('form');
    final matching = forms
        .where((form) => form.id == 'friendform_${submission.userId}')
        .toList();
    if (matching.length != 1) {
      throw const FormatException('friend_removal_form');
    }
    final form = matching.single;
    final action = Uri.tryParse(form.attributes['action'] ?? '');
    if (action == null) throw const FormatException('friend_removal_action');
    final target = config.siteOrigin.resolveUri(action);
    if (!discuzFriendSameSite(target, config.siteOrigin) ||
        target.path != '/home.php' ||
        target.hasFragment ||
        target.queryParametersAll.values.any((values) => values.length != 1) ||
        target.queryParameters['mod'] != 'spacecp' ||
        target.queryParameters['ac'] != 'friend' ||
        target.queryParameters['op'] != 'ignore' ||
        target.queryParameters['uid'] != submission.userId ||
        target.queryParameters['confirm'] != '1' ||
        !target.queryParameters.keys.every(
          {'mod', 'ac', 'op', 'uid', 'confirm', 'mobile'}.contains,
        ) ||
        form.attributes['method']?.toLowerCase() != 'post') {
      throw const FormatException('friend_removal_action');
    }
    final values = <String, String>{};
    for (final control in form.querySelectorAll(
      'input[name], select[name], textarea[name]',
    )) {
      if (discuzControlDisabled(control)) continue;
      final name = control.attributes['name']!;
      if (!{
            'referer',
            'friendsubmit',
            'formhash',
            'from',
            'handlekey',
          }.contains(name) ||
          control.localName != 'input' ||
          control.attributes['type']?.toLowerCase() != 'hidden' ||
          values.containsKey(name)) {
        throw const FormatException('friend_removal_controls');
      }
      values[name] = control.attributes['value'] ?? '';
    }
    final hash = values['formhash'];
    if (values['friendsubmit'] != 'true' ||
        hash == null ||
        !RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(hash)) {
      throw const FormatException('friend_removal_hash');
    }
    return hash;
  }

  _Outcome _outcome(String source, String userId) {
    var payload = source;
    if (source.contains('<![CDATA[')) {
      final envelope = RegExp(
        r'^\s*(?:<\?xml[^>]*\?>\s*)?<root>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</root>\s*$',
      ).firstMatch(source);
      if (envelope == null) return _Outcome.unknown;
      payload = envelope.group(1)!;
      if (payload.contains('<![CDATA[') || payload.contains(']]>')) {
        return _Outcome.unknown;
      }
    }
    final document = html.parse(payload);
    if (document.querySelector('form') != null) return _Outcome.unknown;
    const quoted = r'''(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''';
    final call = RegExp(
      '^\\s*if\\s*\\(\\s*typeof\\s+(succeedhandle|errorhandle)_$_handle\\s*==\\s*[\'"]function[\'"]\\s*\\)\\s*\\{\\s*\\1_$_handle\\s*\\(\\s*($quoted)\\s*,\\s*(?:($quoted)\\s*,\\s*)?(\\{[^{}]*\\})\\s*\\)\\s*;\\s*\\}',
    );
    final matches = [
      for (final script in document.querySelectorAll('script'))
        if (call.firstMatch(script.text) case final match?)
          (match, script.text),
    ];
    if (matches.length != 1) return _Outcome.unknown;
    final (match, script) = matches.single;
    if (script.substring(match.end).contains('handle_$_handle')) {
      return _Outcome.unknown;
    }
    try {
      final values = DiscuzFriendLiteralParser().parse(match.group(4)!);
      if (match.group(1) == 'errorhandle') {
        return match.group(3) == null ? _Outcome.rejected : _Outcome.unknown;
      }
      if (match.group(3) == null ||
          values.length != 2 ||
          values['uid'] != userId ||
          values['from'] != '') {
        return _Outcome.unknown;
      }
      final redirect = DiscuzFriendLiteralParser().parse(
        "{'url':${match.group(2)!}}",
      )['url'];
      if (redirect is! String) return _Outcome.unknown;
      final uri = config.siteOrigin.resolve(redirect);
      return discuzFriendSameSite(uri, config.siteOrigin) &&
              uri.path == '/home.php' &&
              !uri.hasFragment &&
              uri.queryParametersAll.values.every(
                (values) => values.length == 1,
              ) &&
              uri.queryParameters.length == 3 &&
              uri.queryParameters['mod'] == 'spacecp' &&
              uri.queryParameters['ac'] == 'friend' &&
              uri.queryParameters['op'] == 'request'
          ? _Outcome.applied
          : _Outcome.unknown;
    } on FormatException {
      return _Outcome.unknown;
    }
  }
}

const _handle = 'y300_friend_remove';

enum _Outcome { applied, rejected, unknown }

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
DataCommandNotSent<ForumFriendRemovalReceipt> _notSent(
  String code,
  DataCommandFailureKind kind,
) => DataCommandNotSent(
  _failure(code, kind, DataCommandRetryPolicy.explicitOnly),
);
DataCommandNotSent<ForumFriendRemovalReceipt> _cancelled() =>
    _notSent('friend_removal_cancelled', DataCommandFailureKind.cancelled);
DataCommandOutcomeUnknown<ForumFriendRemovalReceipt> _unknown(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.parse,
]) => DataCommandOutcomeUnknown(
  _failure(code, kind, DataCommandRetryPolicy.never),
);
