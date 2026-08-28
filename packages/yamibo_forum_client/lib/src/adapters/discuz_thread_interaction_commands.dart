import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_interaction_commands.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';

/// Experimental Discuz HTML/AJAX adapter for rating preparation and commands.
final class DiscuzThreadPostRatingAdapter
    implements ThreadPostRatingPreparationRepository, ThreadPostRatingCommand {
  /// Creates an adapter on the shared Host transport.
  const DiscuzThreadPostRatingAdapter({
    required this.config,
    required this.network,
    required this.requestProfiles,
  });

  /// Forum origins used to construct and validate endpoints.
  final ForumClientConfig config;

  /// Shared Cookie/WAF-aware transport.
  final ForumClientNetwork network;

  /// Request identity resolver supplied by the Host composition root.
  final ForumRequestProfileResolver requestProfiles;

  @override
  ThreadPostRatingCapabilities get capabilities => _ratingCapabilities;

  @override
  Future<
    DataReadResult<ThreadPostRatingPreparation, ThreadPostRatingCapabilities>
  >
  load(ThreadPostRatingPreparationRequest request) async {
    final tid = request.tid.trim();
    final pid = request.pid.trim();
    if (!_positive(tid) || !_positive(pid)) {
      return _readFailure('thread_post_rating_identity_invalid');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledRead();
    }
    final referer = _safeReferer(request.referer, tid: tid);
    final uri = config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'misc',
        'action': 'rate',
        'tid': tid,
        'pid': pid,
        'infloat': 'yes',
        'handlekey': 'rate',
        'inajax': '1',
      },
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.post.rate.form',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
            .headers,
        cancellation: request.cancellation,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _readTransportFailure(failure);
    }
    try {
      final value =
          (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
      if (value.body is! String) {
        throw const FormatException('thread_post_rating_form_text_expected');
      }
      final parsed = _parseRatingForm(
        value.body as String,
        expectedTid: tid,
        expectedPid: pid,
        fallbackReferer: referer,
      );
      return DataReadSuccess(
        data: parsed,
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _readParseFailure('thread_post_rating_form_parse_failed', error);
    }
  }

  @override
  Future<DataCommandResult<ThreadPostRatingReceipt>> execute(
    ThreadPostRatingSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _DiscuzRatingPreparationToken || token.owner != this) {
      return _notSent('thread_post_rating_preparation_invalid');
    }
    if (preparation.tid != token.tid || preparation.pid != token.pid) {
      return _notSent('thread_post_rating_identity_mismatch');
    }
    final reason = submission.reason.trim();
    if (reason.isEmpty) {
      return _notSent('thread_post_rating_reason_empty');
    }
    final expectedIds = token.dimensions.map((item) => item.id).toSet();
    if (submission.scores.length != expectedIds.length ||
        !submission.scores.keys.toSet().containsAll(expectedIds)) {
      return _notSent('thread_post_rating_scores_incomplete');
    }
    for (final dimension in token.dimensions) {
      final score = submission.scores[dimension.id];
      if (score == null ||
          score < dimension.minimum ||
          score > dimension.maximum) {
        return _notSent('thread_post_rating_score_out_of_range');
      }
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final notifyAuthor = switch (token.notificationPolicy) {
      ThreadPostRatingNotificationPolicy.required => true,
      ThreadPostRatingNotificationPolicy.optional => submission.notifyAuthor,
      ThreadPostRatingNotificationPolicy.unavailable => false,
    };
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: token.actionUri,
        context: const ForumRequestContext(
          operation: 'thread.post.rate.submit',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(
              ForumRequestProfileKind.desktopHtml,
              referer: token.referer,
            )
            .headers,
        body: <String, String>{
          'formhash': token.formhash,
          'tid': token.tid,
          'pid': token.pid,
          if (token.referer.toString().isNotEmpty)
            'referer': token.referer.toString(),
          'handlekey': token.handleKey,
          for (final entry in submission.scores.entries)
            entry.key: entry.value.toString(),
          'reason': reason,
          if (notifyAuthor) 'sendreasonpm': 'on',
          'ratesubmit': 'true',
        },
        cancellation: submission.cancellation,
      ),
    );
    return _ratingCommandResult(response, tid: token.tid, pid: token.pid);
  }

  ThreadPostRatingPreparation _parseRatingForm(
    String source, {
    required String expectedTid,
    required String expectedPid,
    required Uri fallbackReferer,
  }) {
    final document = html_parser.parse(_cdata(source) ?? source);
    final form = document.querySelector('form#rateform');
    if (form == null) {
      throw const FormatException('thread_post_rating_form_missing');
    }
    _rejectSecurityChallengeFields(form, operation: 'rating');
    final formhash = _fieldValue(form, 'formhash');
    final tid = _fieldValue(form, 'tid');
    final pid = _fieldValue(form, 'pid');
    if (formhash.isEmpty || tid != expectedTid || pid != expectedPid) {
      throw const FormatException('thread_post_rating_form_identity_invalid');
    }
    final actionUri = _validatedAction(
      form.attributes['action'],
      expectedMod: 'misc',
      expectedAction: 'rate',
      requiredFlag: 'ratesubmit',
      handleKey: 'rate',
    );
    final referer =
        _sameSiteUri(_fieldValue(form, 'referer')) ?? fallbackReferer;
    final dimensions = <ThreadPostRatingDimension>[];
    final seenIds = <String>{};
    for (final input in form.querySelectorAll('input[name^="score"]')) {
      final id = input.attributes['name']?.trim() ?? '';
      if (!RegExp(r'^score\d+$').hasMatch(id) || !seenIds.add(id)) {
        throw const FormatException('thread_post_rating_dimension_invalid');
      }
      final row = _ancestor(input, 'tr');
      final cells = row?.querySelectorAll('td') ?? const <html_dom.Element>[];
      if (cells.length < 3) {
        throw const FormatException('thread_post_rating_range_missing');
      }
      final range = RegExp(
        r'(-?\d+)\s*~\s*(-?\d+)',
      ).firstMatch(_clean(cells[2].text));
      final minimum = int.tryParse(range?.group(1) ?? '');
      final maximum = int.tryParse(range?.group(2) ?? '');
      if (minimum == null || maximum == null || minimum > maximum) {
        throw const FormatException('thread_post_rating_range_invalid');
      }
      final initialScore = int.tryParse(
        input.attributes['value']?.trim() ?? '',
      );
      if (initialScore == null ||
          initialScore < minimum ||
          initialScore > maximum) {
        throw const FormatException('thread_post_rating_initial_score_invalid');
      }
      final remaining = cells.length > 3
          ? int.tryParse(
              RegExp(r'-?\d+').firstMatch(_clean(cells[3].text))?.group(0) ??
                  '',
            )
          : null;
      dimensions.add(
        ThreadPostRatingDimension(
          id: id,
          label: _clean(cells.first.text),
          minimum: minimum,
          maximum: maximum,
          initialScore: initialScore,
          todayRemaining: remaining ?? 0,
        ),
      );
    }
    if (dimensions.isEmpty) {
      throw const FormatException('thread_post_rating_dimensions_missing');
    }
    final reasonSuggestions = form
        .querySelectorAll('#reasonselect li')
        .map((node) => _clean(node.text))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final notify = form.querySelector('input[name="sendreasonpm"]');
    final notificationPolicy = notify == null
        ? ThreadPostRatingNotificationPolicy.unavailable
        : notify.attributes.containsKey('disabled')
        ? ThreadPostRatingNotificationPolicy.required
        : ThreadPostRatingNotificationPolicy.optional;
    final notifyDefault = notify?.attributes.containsKey('checked') ?? false;
    final token = _DiscuzRatingPreparationToken(
      owner: this,
      actionUri: actionUri,
      formhash: formhash,
      tid: tid,
      pid: pid,
      referer: referer,
      handleKey: _fieldValue(form, 'handlekey').isEmpty
          ? 'rate'
          : _fieldValue(form, 'handlekey'),
      dimensions: List.unmodifiable(dimensions),
      notificationPolicy: notificationPolicy,
    );
    return ThreadPostRatingPreparation(
      tid: tid,
      pid: pid,
      dimensions: token.dimensions,
      reasonSuggestions: List.unmodifiable(reasonSuggestions),
      notificationPolicy: notificationPolicy,
      notifyAuthorByDefault: notifyDefault,
      token: token,
    );
  }

  DataCommandResult<ThreadPostRatingReceipt> _ratingCommandResult(
    ForumTransportResult<ForumResponse<Object?>> response, {
    required String tid,
    required String pid,
  }) {
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(
        _commandTransportFailure(failure, sent: true),
      );
    }
    final body = (response as ForumTransportSuccess<ForumResponse<Object?>>)
        .response
        .body;
    final outcome = _parseCommandOutcome(
      body,
      handleKey: 'rate',
      successCodes: const <String>{'thread_rate_succeed', 'rate_succeed'},
    );
    return switch (outcome) {
      _CommandApplied() => DataCommandApplied(
        ThreadPostRatingReceipt(tid: tid, pid: pid),
      ),
      _CommandRejected(:final code) => DataCommandRejected(
        _commandRejectedFailure(code),
      ),
      _CommandUnproved(:final code) => DataCommandOutcomeUnknown(
        _commandUnprovedFailure(code),
      ),
    };
  }

  Uri _safeReferer(Uri? candidate, {required String tid}) =>
      _sameSiteUri(candidate?.toString() ?? '') ??
      config.siteOrigin.replace(
        path: '/forum.php',
        queryParameters: <String, String>{'mod': 'viewthread', 'tid': tid},
      );

  Uri? _sameSiteUri(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null) return null;
    final resolved = uri.hasScheme ? uri : config.siteOrigin.resolveUri(uri);
    return _sameOrigin(resolved, config.siteOrigin) ? resolved : null;
  }

  Uri _validatedAction(
    String? source, {
    required String expectedMod,
    required String expectedAction,
    required String requiredFlag,
    required String handleKey,
  }) {
    final resolved = _sameSiteUri(source ?? '');
    if (resolved == null ||
        resolved.path != '/forum.php' ||
        resolved.queryParameters['mod'] != expectedMod ||
        resolved.queryParameters['action'] != expectedAction ||
        resolved.queryParameters[requiredFlag] != 'yes') {
      throw const FormatException('thread_interaction_action_invalid');
    }
    return resolved.replace(
      queryParameters: <String, String>{
        ...resolved.queryParameters,
        'inajax': '1',
        'handlekey': handleKey,
      },
      fragment: '',
    );
  }
}

/// Experimental Discuz HTML/AJAX adapter for comment preparation and commands.
final class DiscuzThreadPostCommentAdapter
    implements
        ThreadPostCommentPreparationRepository,
        ThreadPostCommentCommand {
  /// Creates an adapter on the shared Host transport.
  const DiscuzThreadPostCommentAdapter({
    required this.config,
    required this.network,
    required this.requestProfiles,
  });

  /// Forum origins used to construct and validate endpoints.
  final ForumClientConfig config;

  /// Shared Cookie/WAF-aware transport.
  final ForumClientNetwork network;

  /// Request identity resolver supplied by the Host composition root.
  final ForumRequestProfileResolver requestProfiles;

  @override
  ThreadPostCommentCapabilities get capabilities => _commentCapabilities;

  @override
  Future<
    DataReadResult<ThreadPostCommentPreparation, ThreadPostCommentCapabilities>
  >
  load(ThreadPostCommentPreparationRequest request) async {
    final tid = request.tid.trim();
    final pid = request.pid.trim();
    if (!_positive(tid) || !_positive(pid) || request.page < 1) {
      return _readFailure('thread_post_comment_identity_invalid');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledRead();
    }
    final referer = _safeReferer(request.referer, tid: tid);
    final uri = config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'misc',
        'action': 'comment',
        'tid': tid,
        'pid': pid,
        'extra': '',
        'page': request.page.toString(),
        'infloat': 'yes',
        'handlekey': 'comment',
        'inajax': '1',
        'ajaxtarget': 'fwin_content_comment',
      },
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.post.comment.form',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
            .headers,
        cancellation: request.cancellation,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _readTransportFailure(failure);
    }
    try {
      final value =
          (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
      if (value.body is! String) {
        throw const FormatException('thread_post_comment_form_text_expected');
      }
      final preparation = _parseCommentForm(
        value.body as String,
        expectedTid: tid,
        expectedPid: pid,
        fallbackReferer: referer,
      );
      return DataReadSuccess(
        data: preparation,
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _readParseFailure('thread_post_comment_form_parse_failed', error);
    }
  }

  @override
  Future<DataCommandResult<ThreadPostCommentReceipt>> execute(
    ThreadPostCommentSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _DiscuzCommentPreparationToken || token.owner != this) {
      return _notSent('thread_post_comment_preparation_invalid');
    }
    if (preparation.tid != token.tid || preparation.pid != token.pid) {
      return _notSent('thread_post_comment_identity_mismatch');
    }
    final message = submission.message.trim();
    if (message.isEmpty) {
      return _notSent('thread_post_comment_message_empty');
    }
    if (preparation.maxLength > 0 && message.length > preparation.maxLength) {
      return _notSent('thread_post_comment_message_too_long');
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: token.actionUri,
        context: const ForumRequestContext(
          operation: 'thread.post.comment.submit',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(
              ForumRequestProfileKind.desktopHtml,
              referer: token.referer,
            )
            .headers,
        body: <String, String>{
          'formhash': token.formhash,
          'handlekey': token.handleKey,
          'message': message,
          'commentsubmit': 'true',
        },
        cancellation: submission.cancellation,
      ),
    );
    return _commentCommandResult(response, tid: token.tid, pid: token.pid);
  }

  ThreadPostCommentPreparation _parseCommentForm(
    String source, {
    required String expectedTid,
    required String expectedPid,
    required Uri fallbackReferer,
  }) {
    final document = html_parser.parse(_cdata(source) ?? source);
    final form = document.querySelector('form#commentform');
    if (form == null) {
      throw const FormatException('thread_post_comment_form_missing');
    }
    _rejectSecurityChallengeFields(form, operation: 'comment');
    if (form.querySelector('[name="commentitem"]') != null) {
      throw const FormatException('thread_post_comment_items_unsupported');
    }
    final formhash = _fieldValue(form, 'formhash');
    if (formhash.isEmpty) {
      throw const FormatException('thread_post_comment_formhash_missing');
    }
    final actionUri = _validatedCommentAction(
      form.attributes['action'],
      expectedTid: expectedTid,
      expectedPid: expectedPid,
    );
    final maxLength =
        int.tryParse(
          RegExp(r'\d+')
                  .firstMatch(
                    _clean(document.querySelector('#checklen')?.text ?? ''),
                  )
                  ?.group(0) ??
              '',
        ) ??
        200;
    if (maxLength < 1) {
      throw const FormatException('thread_post_comment_limit_invalid');
    }
    final token = _DiscuzCommentPreparationToken(
      owner: this,
      actionUri: actionUri,
      formhash: formhash,
      tid: expectedTid,
      pid: expectedPid,
      referer: fallbackReferer,
      handleKey: _fieldValue(form, 'handlekey').isEmpty
          ? 'comment'
          : _fieldValue(form, 'handlekey'),
    );
    return ThreadPostCommentPreparation(
      tid: expectedTid,
      pid: expectedPid,
      maxLength: maxLength,
      token: token,
    );
  }

  Uri _validatedCommentAction(
    String? source, {
    required String expectedTid,
    required String expectedPid,
  }) {
    final resolved = _sameSiteUri(source ?? '');
    if (resolved == null ||
        resolved.path != '/forum.php' ||
        resolved.queryParameters['mod'] != 'post' ||
        resolved.queryParameters['action'] != 'reply' ||
        resolved.queryParameters['comment'] != 'yes' ||
        resolved.queryParameters['commentsubmit'] != 'yes' ||
        resolved.queryParameters['tid'] != expectedTid ||
        resolved.queryParameters['pid'] != expectedPid) {
      throw const FormatException('thread_post_comment_action_invalid');
    }
    return resolved.replace(
      queryParameters: <String, String>{
        ...resolved.queryParameters,
        'inajax': '1',
        'handlekey': 'comment',
      },
      fragment: '',
    );
  }

  DataCommandResult<ThreadPostCommentReceipt> _commentCommandResult(
    ForumTransportResult<ForumResponse<Object?>> response, {
    required String tid,
    required String pid,
  }) {
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(
        _commandTransportFailure(failure, sent: true),
      );
    }
    final body = (response as ForumTransportSuccess<ForumResponse<Object?>>)
        .response
        .body;
    final outcome = _parseCommandOutcome(
      body,
      handleKey: 'comment',
      successCodes: const <String>{'comment_add_succeed'},
      expectedTid: tid,
      expectedPid: pid,
    );
    return switch (outcome) {
      _CommandApplied() => DataCommandApplied(
        ThreadPostCommentReceipt(tid: tid, pid: pid),
      ),
      _CommandRejected(:final code) => DataCommandRejected(
        _commandRejectedFailure(code),
      ),
      _CommandUnproved(:final code) => DataCommandOutcomeUnknown(
        _commandUnprovedFailure(code),
      ),
    };
  }

  Uri _safeReferer(Uri? candidate, {required String tid}) =>
      _sameSiteUri(candidate?.toString() ?? '') ??
      config.siteOrigin.replace(
        path: '/forum.php',
        queryParameters: <String, String>{'mod': 'viewthread', 'tid': tid},
      );

  Uri? _sameSiteUri(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null) return null;
    final resolved = uri.hasScheme ? uri : config.siteOrigin.resolveUri(uri);
    return _sameOrigin(resolved, config.siteOrigin) ? resolved : null;
  }
}

final class _DiscuzRatingPreparationToken
    implements ThreadPostRatingPreparationToken {
  const _DiscuzRatingPreparationToken({
    required this.owner,
    required this.actionUri,
    required this.formhash,
    required this.tid,
    required this.pid,
    required this.referer,
    required this.handleKey,
    required this.dimensions,
    required this.notificationPolicy,
  });

  final DiscuzThreadPostRatingAdapter owner;
  final Uri actionUri;
  final String formhash;
  final String tid;
  final String pid;
  final Uri referer;
  final String handleKey;
  final List<ThreadPostRatingDimension> dimensions;
  final ThreadPostRatingNotificationPolicy notificationPolicy;

  @override
  String toString() => '_DiscuzRatingPreparationToken(redacted)';
}

final class _DiscuzCommentPreparationToken
    implements ThreadPostCommentPreparationToken {
  const _DiscuzCommentPreparationToken({
    required this.owner,
    required this.actionUri,
    required this.formhash,
    required this.tid,
    required this.pid,
    required this.referer,
    required this.handleKey,
  });

  final DiscuzThreadPostCommentAdapter owner;
  final Uri actionUri;
  final String formhash;
  final String tid;
  final String pid;
  final Uri referer;
  final String handleKey;

  @override
  String toString() => '_DiscuzCommentPreparationToken(redacted)';
}

sealed class _CommandOutcome {
  const _CommandOutcome();
}

final class _CommandApplied extends _CommandOutcome {
  const _CommandApplied();
}

final class _CommandRejected extends _CommandOutcome {
  const _CommandRejected(this.code);
  final String code;
}

final class _CommandUnproved extends _CommandOutcome {
  const _CommandUnproved(this.code);
  final String code;
}

_CommandOutcome _parseCommandOutcome(
  Object? body, {
  required String handleKey,
  required Set<String> successCodes,
  String? expectedTid,
  String? expectedPid,
}) {
  final source = body is String ? body.trim() : '';
  if (source.isEmpty) {
    return const _CommandUnproved('thread_interaction_response_empty');
  }
  final json = _tryJson(source);
  if (json != null) {
    final message = _asMap(json['Message']);
    final code = message['messageval']?.toString().trim() ?? '';
    if (successCodes.contains(code)) return const _CommandApplied();
    if (code.isNotEmpty) return _CommandRejected(code);
    return const _CommandUnproved('thread_interaction_json_unproved');
  }
  final payload = _cdata(source) ?? source;
  if (RegExp(
    'errorhandle_${RegExp.escape(handleKey)}\\s*\\(',
    caseSensitive: false,
  ).hasMatch(payload)) {
    return _CommandRejected('thread_post_${handleKey}_rejected');
  }
  final success = RegExp(
    'succeedhandle_${RegExp.escape(handleKey)}\\s*\\(',
    caseSensitive: false,
  ).hasMatch(payload);
  if (!success) {
    return const _CommandUnproved('thread_interaction_callback_missing');
  }
  if (expectedTid != null && expectedPid != null) {
    final tid = RegExp(
      r'''["']tid["']\s*:\s*["'](\d+)["']''',
      caseSensitive: false,
    ).firstMatch(payload)?.group(1);
    final pid = RegExp(
      r'''["']pid["']\s*:\s*["'](\d+)["']''',
      caseSensitive: false,
    ).firstMatch(payload)?.group(1);
    if ((tid != null && tid != expectedTid) ||
        (pid != null && pid != expectedPid)) {
      return const _CommandUnproved('thread_interaction_identity_mismatch');
    }
  }
  return const _CommandApplied();
}

Map<String, Object?>? _tryJson(String source) {
  if (!source.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(source);
    return _asMap(decoded);
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _asMap(Object? source) => source is Map
    ? source.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

void _rejectSecurityChallengeFields(
  html_dom.Element form, {
  required String operation,
}) {
  const names = <String>{
    'seccodeverify',
    'secanswer',
    'sechash',
    'seccodehash',
  };
  for (final element in form.querySelectorAll('[name]')) {
    final name = element.attributes['name']?.trim().toLowerCase();
    if (name != null && names.contains(name)) {
      throw FormatException('thread_post_${operation}_security_unsupported');
    }
  }
}

String _fieldValue(html_dom.Element form, String name) =>
    form.querySelector('[name="$name"]')?.attributes['value']?.trim() ?? '';

html_dom.Element? _ancestor(html_dom.Element element, String localName) {
  html_dom.Element? current = element.parent;
  while (current != null) {
    if (current.localName == localName) return current;
    current = current.parent;
  }
  return null;
}

String _clean(String source) =>
    source.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String? _cdata(String source) => RegExp(
  r'<!\[CDATA\[([\s\S]*?)\]\]>',
  caseSensitive: false,
).firstMatch(source)?.group(1);

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value.trim());

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

DataReadFailure<T, C> _readFailure<T, C>(String code) => DataReadFailure(
  kind: DataReadFailureKind.business,
  code: code,
  diagnosticMessage: code,
);

DataReadFailure<T, C> _cancelledRead<T, C>() => const DataReadFailure(
  kind: DataReadFailureKind.cancelled,
  code: 'request_cancelled',
  diagnosticMessage: 'request_cancelled',
);

DataReadFailure<T, C> _readParseFailure<T, C>(
  String code,
  FormatException error,
) => DataReadFailure(
  kind: DataReadFailureKind.parse,
  code: code,
  diagnosticMessage: error.message.toString(),
);

DataReadFailure<T, C> _readTransportFailure<T, C>(
  ForumTransportFailure failure,
) => DataReadFailure(
  kind: toReadFailureKind(failure.kind),
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

DataCommandNotSent<T> _notSent<T>(String code) => DataCommandNotSent(
  DataCommandFailure(
    kind: DataCommandFailureKind.validation,
    retryPolicy: DataCommandRetryPolicy.afterInputChange,
    code: code,
    diagnosticMessage: code,
  ),
);

DataCommandNotSent<T> _cancelledNotSent<T>() => const DataCommandNotSent(
  DataCommandFailure(
    kind: DataCommandFailureKind.cancelled,
    retryPolicy: DataCommandRetryPolicy.never,
    code: 'request_cancelled',
    diagnosticMessage: 'request_cancelled',
  ),
);

DataCommandFailure _commandRejectedFailure(String code) => DataCommandFailure(
  kind: code.toLowerCase().contains('formhash')
      ? DataCommandFailureKind.staleFormhash
      : DataCommandFailureKind.permissionDenied,
  retryPolicy: code.toLowerCase().contains('formhash')
      ? DataCommandRetryPolicy.afterSessionRefresh
      : DataCommandRetryPolicy.explicitOnly,
  code: code,
  diagnosticMessage: code,
);

DataCommandFailure _commandUnprovedFailure(String code) => DataCommandFailure(
  kind: DataCommandFailureKind.parse,
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: code,
  diagnosticMessage: code,
);

DataCommandFailure _commandTransportFailure(
  ForumTransportFailure failure, {
  required bool sent,
}) => DataCommandFailure(
  kind: failure.statusCode == 405
      ? DataCommandFailureKind.securityChallenge
      : switch (failure.kind) {
          ForumTransportFailureKind.network => DataCommandFailureKind.network,
          ForumTransportFailureKind.timeout => DataCommandFailureKind.timeout,
          ForumTransportFailureKind.server => DataCommandFailureKind.server,
          ForumTransportFailureKind.unauthorized =>
            DataCommandFailureKind.unauthenticated,
          ForumTransportFailureKind.parse => DataCommandFailureKind.parse,
          ForumTransportFailureKind.business => DataCommandFailureKind.unknown,
          ForumTransportFailureKind.cancelled =>
            DataCommandFailureKind.cancelled,
          ForumTransportFailureKind.unknown => DataCommandFailureKind.unknown,
        },
  retryPolicy: sent
      ? DataCommandRetryPolicy.explicitOnly
      : DataCommandRetryPolicy.never,
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

final _ratingCapabilities = ThreadPostRatingCapabilities(
  values: DataCapabilitySet.supported(ThreadPostRatingCapability.values),
);

final _commentCapabilities = ThreadPostCommentCapabilities(
  values: DataCapabilitySet.supported(ThreadPostCommentCapability.values),
);
