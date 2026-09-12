import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_composer_commands.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import 'discuz_api_client.dart';
import 'discuz_thread_creation_form_parser.dart';

/// Mobile HTML preparation with Discuz v4 creation commands.
final class DiscuzThreadCreationAdapter
    implements ThreadCreationPreparationRepository, ThreadCreationCommand {
  /// Creates an adapter on the shared API transport and formhash source.
  const DiscuzThreadCreationAdapter({
    required this.api,
    required this.config,
    required this.formhashProvider,
    required this.network,
    required this.requestProfiles,
  });

  /// Discuz API decoder and transport.
  final DiscuzApiClient api;

  /// Forum origins used to construct safe Referer values.
  final ForumClientConfig config;

  /// Canonical package formhash source.
  final ForumFormhashProvider formhashProvider;

  /// Shared host transport used for mobile HTML preparation.
  final ForumClientNetwork network;

  /// User-agent and referer policy for the shared transport.
  final ForumRequestProfileResolver requestProfiles;

  @override
  ThreadCreationCapabilities get capabilities => _creationCapabilities;

  @override
  Future<DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>>
  load(ThreadCreationPreparationRequest request) async {
    final fid = request.fid.trim();
    if (!_positive(fid)) {
      return _readFailure('thread_creation_forum_identity_invalid');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledRead();
    }
    final uri = config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: {
        'mod': 'post',
        'action': 'newthread',
        'fid': fid,
        'mobile': '2',
        if (request.kind == ThreadCreationKind.poll) ...{
          'special': '1',
          'cedit': 'yes',
        },
      },
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.creation.prepare',
          pageKind: 'thread.creation.form',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml, referer: uri)
            .headers,
        cancellation: request.cancellation,
      ),
    );
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _readTransportFailure(failure);
    }
    if (request.cancellation?.isCancelled ?? false) return _cancelledRead();
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    try {
      if (response.body is! String) {
        throw const FormatException('thread_creation_form_not_text');
      }
      final form = const DiscuzThreadCreationFormParser().parse(
        response.body as String,
        sourceUri: response.uri,
        requestedUri: uri,
        fid: fid,
        kind: request.kind,
      );
      return DataReadSuccess(
        data: ThreadCreationPreparation(
          fid: fid,
          forumName: '',
          kind: form.kind,
          threadTypes: form.types,
          threadSorts: const [],
          typeRequired: form.typeRequired,
          sortRequired: false,
          maxSubjectLength: form.maximumSubjectLength,
          maxMessageLength: form.maximumMessageLength,
          readAccess: form.readAccess,
          pollConstraints: form.pollConstraints,
          token: _DiscuzThreadCreationToken(owner: this, form: form),
        ),
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } on DiscuzCreationFormFailure catch (error) {
      return DataReadFailure(
        kind: error.kind,
        code: error.code,
        diagnosticMessage: error.code,
      );
    } on FormatException catch (error) {
      return _readParseFailure(
        'thread_creation_preparation_parse_failed',
        error,
      );
    }
  }

  @override
  Future<DataCommandResult<ThreadCreationReceipt>> execute(
    ThreadCreationSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _DiscuzThreadCreationToken || token.owner != this) {
      return _notSent('thread_creation_preparation_invalid');
    }
    if (preparation.fid != token.fid ||
        preparation.kind != token.form.kind ||
        submission.kind != token.form.kind) {
      return _notSent('thread_creation_preparation_identity_mismatch');
    }
    final validation = _validateCreation(submission, token);
    if (validation != null) return _notSent(validation);
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final form = _creationForm(submission, token);
    final result = await api.postForm(
      module: 'newthread',
      queryParameters: <String, Object?>{'version': '4', 'fid': token.fid},
      form: form,
      treatMessageAsBusinessError: false,
      referer: token.form.sourceUri,
      cancellation: submission.cancellation,
    );
    if (result case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(_commandTransportFailure(failure));
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response;
    final envelope = response.body;
    if (envelope.version != '4') {
      return _outcomeUnknown('thread_creation_response_version_invalid');
    }
    final code = _messageCode(envelope);
    const successCodes = <String>{
      'post_newthread_succeed',
      'post_newthread_mod_succeed',
    };
    if (!successCodes.contains(code)) {
      return code.isEmpty
          ? _outcomeUnknown('thread_creation_success_unproved')
          : DataCommandRejected(_commandRejectedFailure(code));
    }
    final tid = _text(envelope.variables['tid']);
    final pid = _text(envelope.variables['pid']);
    if (!_positive(tid) || !_positive(pid)) {
      return _outcomeUnknown('thread_creation_receipt_identity_invalid');
    }
    final readAccess = await _readAccessEvidence(
      tid: tid,
      requested: submission.minimumReadAccess,
      cancellation: submission.cancellation,
    );
    return DataCommandApplied(
      ThreadCreationReceipt(
        tid: tid,
        pid: pid,
        publicationState: code == 'post_newthread_mod_succeed'
            ? ThreadPublicationState.pendingModeration
            : ThreadPublicationState.published,
        readAccess: readAccess,
      ),
    );
  }

  String? _validateCreation(
    ThreadCreationSubmission submission,
    _DiscuzThreadCreationToken token,
  ) {
    final subject = submission.subject;
    final message = submission.message;
    if (subject.trim().isEmpty) return 'thread_creation_subject_empty';
    if (message.trim().isEmpty) return 'thread_creation_message_empty';
    if ((token.maxSubjectLength ?? 0) > 0 &&
        subject.length > token.maxSubjectLength!) {
      return 'thread_creation_subject_too_long';
    }
    if ((token.maxMessageLength ?? 0) > 0 &&
        message.length > token.maxMessageLength!) {
      return 'thread_creation_message_too_long';
    }
    final typeId = submission.typeId.trim();
    if (typeId != '0' && !token.allowedTypeIds.contains(typeId)) {
      return 'thread_creation_type_invalid';
    }
    if (token.typeRequired == true && typeId == '0') {
      return 'post_type_isnull';
    }
    if (submission.minimumReadAccess < 0 ||
        submission.minimumReadAccess > 255) {
      return 'thread_creation_read_access_invalid';
    }
    if (!_validPositiveUnique(submission.attachmentIds)) {
      return 'thread_creation_attachment_identity_invalid';
    }
    final access = token.form.readAccess;
    if (access.canModify
        ? !access.allows(submission.minimumReadAccess)
        : submission.minimumReadAccess != (access.currentValue ?? 0)) {
      return 'thread_creation_read_access_not_allowed';
    }
    final tags = submission.tags;
    if (tags.length > 5 ||
        tags.any(
          (tag) => tag.isEmpty || tag.trim() != tag || tag.length > 16,
        ) ||
        tags.toSet().length != tags.length) {
      return 'thread_creation_tags_invalid';
    }
    switch (submission.kind) {
      case ThreadCreationKind.ordinary:
        if (submission.poll != null) return 'thread_creation_poll_unexpected';
      case ThreadCreationKind.poll:
        final poll = submission.poll;
        if (poll == null) return 'thread_creation_poll_missing';
        if (poll.options.length < 2 ||
            (token.form.pollConstraints?.maximumOptions != null &&
                poll.options.length >
                    token.form.pollConstraints!.maximumOptions!)) {
          return 'thread_creation_poll_option_count_invalid';
        }
        if (poll.options.any(
              (option) =>
                  option.isEmpty ||
                  option.trim() != option ||
                  (token.form.pollConstraints?.maximumOptionLength != null &&
                      option.length >
                          token.form.pollConstraints!.maximumOptionLength!),
            ) ||
            poll.options.toSet().length != poll.options.length) {
          return 'thread_creation_poll_option_invalid';
        }
        if (poll.maximumChoices < 1 ||
            poll.maximumChoices > poll.options.length ||
            poll.expirationDays < 0) {
          return 'thread_creation_poll_fields_invalid';
        }
    }
    return null;
  }

  Map<String, String> _creationForm(
    ThreadCreationSubmission submission,
    _DiscuzThreadCreationToken token,
  ) {
    final form = <String, String>{
      'formhash': token.formhash,
      'posttime': token.form.posttime,
      'topicsubmit': 'yes',
      'subject': submission.subject,
      'message': submission.message,
      'typeid': submission.typeId.trim(),
      if (token.form.readAccess.canModify)
        'readperm': submission.minimumReadAccess.toString(),
      'usesig': submission.useSignature ? '1' : '0',
      'allownoticeauthor': submission.notifyAuthor ? '1' : '0',
      if (submission.disableBbCode) 'bbcodeoff': '1',
      if (submission.disableSmileys) 'smileyoff': '1',
      if (submission.disableUrlParsing) 'parseurloff': '1',
      if (submission.attachmentIds.isNotEmpty) 'allowphoto': '1',
      for (final aid in submission.attachmentIds)
        'attachnew[$aid][description]': '',
      'special': submission.kind == ThreadCreationKind.poll ? '1' : '0',
      if (submission.tags.isNotEmpty) 'tags': submission.tags.join(','),
    };
    final poll = submission.poll;
    if (poll != null) {
      form.addAll(<String, String>{
        'tpolloption': '2',
        'polloptions': poll.options.join('\n'),
        'maxchoices': poll.maximumChoices.toString(),
        'expiration': poll.expirationDays.toString(),
        'overt': poll.publicVoters ? '1' : '0',
        if (poll.resultsAfterVote) 'visibilitypoll': '1',
      });
    }
    return form;
  }

  Future<ThreadReadAccessEvidence> _readAccessEvidence({
    required String tid,
    required int requested,
    ForumRequestCancellation? cancellation,
  }) async {
    if (requested == 0) {
      return const ThreadReadAccessEvidence(
        kind: ThreadReadAccessEvidenceKind.unrestricted,
        requested: 0,
        actual: 0,
      );
    }
    if (cancellation?.isCancelled ?? false) {
      return ThreadReadAccessEvidence(
        kind: ThreadReadAccessEvidenceKind.unverified,
        requested: requested,
      );
    }
    final result = await api.get(
      module: 'viewthread',
      queryParameters: <String, Object?>{'version': '4', 'tid': tid, 'page': 1},
      cancellation: cancellation,
    );
    if (result case ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
      :final response,
    )) {
      final thread = _map(response.body.variables['thread']);
      final actualTid = _text(thread['tid']);
      final actual = _int(thread['readperm']);
      if (response.body.version == '4' &&
          actualTid == tid &&
          actual != null &&
          actual >= 0 &&
          actual <= 255) {
        return ThreadReadAccessEvidence(
          kind: actual == requested
              ? ThreadReadAccessEvidenceKind.confirmed
              : ThreadReadAccessEvidenceKind.serverAdjusted,
          requested: requested,
          actual: actual,
        );
      }
    }
    return ThreadReadAccessEvidence(
      kind: ThreadReadAccessEvidenceKind.unverified,
      requested: requested,
    );
  }
}

/// Experimental Discuz HTML/v4 adapter for reply preparation and commands.
final class DiscuzThreadReplyAdapter
    implements ThreadReplyPreparationRepository, ThreadReplyCommand {
  /// Creates an adapter on the shared Host transport and formhash source.
  const DiscuzThreadReplyAdapter({
    required this.api,
    required this.config,
    required this.network,
    required this.requestProfiles,
    required this.formhashProvider,
  });

  /// Discuz API decoder and transport.
  final DiscuzApiClient api;

  /// Forum origins used for validation and Referer values.
  final ForumClientConfig config;

  /// Shared Cookie/WAF-aware transport used for HTML preparation.
  /// Shared host transport used for mobile HTML preparation.
  final ForumClientNetwork network;

  /// Request identity resolver supplied by the composition root.
  /// User-agent and referer policy for the shared transport.
  final ForumRequestProfileResolver requestProfiles;

  /// Canonical package formhash source.
  final ForumFormhashProvider formhashProvider;

  @override
  ThreadReplyCapabilities get capabilities => _replyCapabilities;

  @override
  Future<DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>> load(
    ThreadReplyPreparationRequest request,
  ) async {
    final target = request.target;
    if (target.kind != ThreadReplyTargetKind.post || !_validTarget(target)) {
      return _readFailure('thread_reply_target_invalid');
    }
    final formUri = _sameSiteUri(request.formUri);
    if (formUri == null || !_isReplyFormUri(formUri)) {
      return _readFailure('thread_reply_form_uri_invalid');
    }
    if (!_uriProvesTarget(formUri, target)) {
      return _readFailure('thread_reply_form_identity_mismatch');
    }
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledRead();
    }
    final desktopFormUri = _withoutMobileMode(formUri);
    final referer = _safeDesktopReferer(request.referer, target.tid);
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: desktopFormUri,
        context: const ForumRequestContext(
          operation: 'thread.reply.prepare',
          pageKind: 'thread.reply.form',
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
        throw const FormatException('thread_reply_form_text_expected');
      }
      final responseUri = _sameSiteUri(value.uri);
      if (responseUri == null || !_isDesktopReplyFormUri(responseUri)) {
        throw const FormatException('thread_reply_desktop_form_uri_invalid');
      }
      final preparation = _parseReplyForm(
        value.body as String,
        sourceUri: desktopFormUri,
        expected: target,
        referer: referer,
      );
      return DataReadSuccess(
        data: preparation,
        capabilities: capabilities,
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _readParseFailure('thread_reply_preparation_parse_failed', error);
    }
  }

  @override
  Future<DataCommandResult<ThreadReplyReceipt>> execute(
    ThreadReplySubmission submission,
  ) async {
    final target = submission.target;
    if (!_validTarget(target) || submission.message.trim().isEmpty) {
      return _notSent('thread_reply_submission_invalid');
    }
    if (!_validPositiveUnique(submission.attachmentIds)) {
      return _notSent('thread_reply_attachment_identity_invalid');
    }
    _DiscuzThreadReplyToken? token;
    if (target.kind == ThreadReplyTargetKind.post) {
      final preparation = submission.preparation;
      final candidate = preparation?.token;
      if (preparation == null ||
          candidate is! _DiscuzThreadReplyToken ||
          candidate.owner != this ||
          !_sameTarget(preparation.target, target) ||
          !_sameTarget(candidate.target, target)) {
        return _notSent('thread_reply_preparation_invalid');
      }
      token = candidate;
    } else if (submission.preparation != null) {
      return _notSent('thread_reply_preparation_unexpected');
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final formhash = await _resolveReplyFormhash(
      token?.formhash,
      cancellation: submission.cancellation,
    );
    if (formhash case ForumFormhashError(:final failure)) {
      return _formhashNotSent(failure);
    }
    final value = (formhash as ForumFormhashSuccess).value;
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final result = await api.postForm(
      module: 'sendreply',
      queryParameters: const <String, Object?>{'version': '4'},
      form: <String, String>{
        'formhash': value,
        'fid': target.fid.trim(),
        'tid': target.tid.trim(),
        'message': submission.message,
        'replysubmit': 'yes',
        'usesig': submission.useSignature ? '1' : '0',
        if (submission.attachmentIds.isNotEmpty) 'allowphoto': '1',
        for (final aid in submission.attachmentIds)
          'attachnew[$aid][description]': '',
        if (token != null) ...token.hiddenFields,
      },
      treatMessageAsBusinessError: false,
      referer: _safeDesktopReferer(token?.referer, target.tid),
      cancellation: submission.cancellation,
    );
    if (result case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return DataCommandOutcomeUnknown(_commandTransportFailure(failure));
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
            .response;
    final envelope = response.body;
    if (envelope.version != '4') {
      return _outcomeUnknown('thread_reply_response_version_invalid');
    }
    final code = _messageCode(envelope);
    const successCodes = <String>{
      'post_reply_succeed',
      'post_reply_mod_succeed',
    };
    if (!successCodes.contains(code)) {
      return code.isEmpty
          ? _outcomeUnknown('thread_reply_success_unproved')
          : DataCommandRejected(_commandRejectedFailure(code));
    }
    final tid = _text(envelope.variables['tid']);
    final pid = _text(envelope.variables['pid']);
    if (tid != target.tid.trim() || !_positive(pid)) {
      return _outcomeUnknown('thread_reply_receipt_identity_invalid');
    }
    return DataCommandApplied(
      ThreadReplyReceipt(
        tid: tid,
        pid: pid,
        publicationState: code == 'post_reply_mod_succeed'
            ? ThreadPublicationState.pendingModeration
            : ThreadPublicationState.published,
      ),
    );
  }

  ThreadReplyPreparation _parseReplyForm(
    String source, {
    required Uri sourceUri,
    required ThreadReplyTarget expected,
    required Uri referer,
  }) {
    final document = html_parser.parse(source);
    final form = document.querySelector('#postform');
    if (form == null) {
      throw const FormatException('thread_reply_form_missing');
    }
    final hidden = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name']?.trim() ?? '';
      if (name.isEmpty) continue;
      hidden[name] = input.attributes['value'] ?? '';
    }
    final actionText = form.attributes['action']?.trim() ?? '';
    Uri? actionUri;
    if (actionText.isNotEmpty) {
      actionUri = _sameSiteUri(
        sourceUri.resolve(actionText.replaceAll('&amp;', '&')),
      );
      if (actionUri == null || !_isReplyFormUri(actionUri)) {
        throw const FormatException('thread_reply_form_action_invalid');
      }
    }
    final identities = <String, List<String>>{
      'fid': <String>[
        ..._queryValues(sourceUri, 'fid'),
        if (actionUri != null) ..._queryValues(actionUri, 'fid'),
        if ((hidden['fid'] ?? '').trim().isNotEmpty) hidden['fid']!.trim(),
      ],
      'tid': <String>[
        ..._queryValues(sourceUri, 'tid'),
        if (actionUri != null) ..._queryValues(actionUri, 'tid'),
        if ((hidden['tid'] ?? '').trim().isNotEmpty) hidden['tid']!.trim(),
      ],
      'pid': <String>[
        ..._queryValues(sourceUri, 'repquote'),
        if (actionUri != null) ..._queryValues(actionUri, 'repquote'),
        for (final name in const <String>['repquote', 'reppid', 'reppost'])
          if ((hidden[name] ?? '').trim().isNotEmpty) hidden[name]!.trim(),
      ],
    };
    _verifyIdentityValues(identities['fid']!, expected.fid, 'fid');
    _verifyIdentityValues(identities['tid']!, expected.tid, 'tid');
    _verifyIdentityValues(identities['pid']!, expected.pid!, 'pid');
    _verifyDesktopQuoteReference(
      hidden['noticetrimstr'] ?? '',
      sourceUri: sourceUri,
      expected: expected,
    );
    final hiddenFields = <String, String>{
      for (final name in const <String>[
        'reppid',
        'reppost',
        'noticeauthor',
        'noticetrimstr',
        'noticeauthormsg',
      ])
        if ((hidden[name] ?? '').trim().isNotEmpty) name: hidden[name]!,
    };
    final noticeAuthorMessage = _clean(hidden['noticeauthormsg'] ?? '');
    final formText = _clean(form.text);
    return ThreadReplyPreparation(
      target: expected,
      // Discuz provides the quoted post body separately from the visible form
      // chrome. Preserve the pre-migration UI semantics and only use the whole
      // form as a compatibility fallback when that field is absent.
      quotePreview: noticeAuthorMessage.isNotEmpty
          ? noticeAuthorMessage
          : (formText.isEmpty ? null : formText),
      token: _DiscuzThreadReplyToken(
        owner: this,
        target: expected,
        formhash: hidden['formhash']?.trim() ?? '',
        hiddenFields: Map<String, String>.unmodifiable(hiddenFields),
        referer: referer,
      ),
    );
  }

  void _verifyIdentityValues(
    List<String> values,
    String expected,
    String field,
  ) {
    final normalized = values
        .map((value) => value.trim())
        .where(_positive)
        .toSet();
    if (normalized.isEmpty ||
        normalized.length != 1 ||
        !normalized.contains(expected.trim())) {
      throw FormatException('thread_reply_${field}_identity_mismatch');
    }
  }

  bool _uriProvesTarget(Uri uri, ThreadReplyTarget target) {
    try {
      _verifyIdentityValues(_queryValues(uri, 'fid'), target.fid, 'fid');
      _verifyIdentityValues(_queryValues(uri, 'tid'), target.tid, 'tid');
      _verifyIdentityValues(_queryValues(uri, 'repquote'), target.pid!, 'pid');
      return true;
    } on FormatException {
      return false;
    }
  }

  bool _isReplyFormUri(Uri uri) {
    if (uri.path != '/forum.php') return false;
    final mod = _singleQuery(uri, 'mod');
    final action = _singleQuery(uri, 'action');
    return mod == 'post' && action == 'reply';
  }

  bool _isDesktopReplyFormUri(Uri uri) {
    if (!_isReplyFormUri(uri)) return false;
    final modes = _queryValues(uri, 'mobile');
    return modes.isEmpty || (modes.length == 1 && modes.single == 'no');
  }

  Uri? _sameSiteUri(Uri uri) {
    final resolved = uri.hasScheme ? uri : config.siteOrigin.resolveUri(uri);
    return _sameOrigin(resolved, config.siteOrigin) ? resolved : null;
  }

  Uri _safeDesktopReferer(Uri? source, String tid) {
    final value = source == null ? null : _sameSiteUri(source);
    return value == null
        ? config.siteOrigin.replace(
            path: '/forum.php',
            queryParameters: <String, String>{'mod': 'viewthread', 'tid': tid},
          )
        : _withoutMobileMode(value);
  }

  Uri _withoutMobileMode(Uri uri) {
    final parameters = <String, Object>{
      for (final entry in uri.queryParametersAll.entries)
        if (entry.key.toLowerCase() != 'mobile')
          entry.key: entry.value.length == 1 ? entry.value.single : entry.value,
    };
    return uri.replace(queryParameters: parameters, fragment: '');
  }

  void _verifyDesktopQuoteReference(
    String raw, {
    required Uri sourceUri,
    required ThreadReplyTarget expected,
  }) {
    final match = RegExp(
      r'\[url=([^\]]+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      throw const FormatException('thread_reply_quote_reference_missing');
    }
    final reference = _sameSiteUri(
      sourceUri.resolve(match.group(1)!.replaceAll('&amp;', '&')),
    );
    if (reference == null ||
        reference.path != '/forum.php' ||
        _singleQuery(reference, 'mod') != 'redirect' ||
        _singleQuery(reference, 'goto') != 'findpost' ||
        _singleQuery(reference, 'pid') != expected.pid ||
        _singleQuery(reference, 'ptid') != expected.tid) {
      throw const FormatException('thread_reply_quote_reference_invalid');
    }
  }

  Future<ForumFormhashResult> _resolveReplyFormhash(
    String? prepared, {
    ForumRequestCancellation? cancellation,
  }) {
    final value = prepared?.trim() ?? '';
    if (value.isNotEmpty) return Future.value(ForumFormhashSuccess(value));
    return formhashProvider.loadFormhash(
      preferProfile: true,
      cancellation: cancellation,
    );
  }
}

final class _DiscuzThreadCreationToken
    implements ThreadCreationPreparationToken {
  const _DiscuzThreadCreationToken({required this.owner, required this.form});
  final DiscuzThreadCreationAdapter owner;
  final DiscuzThreadCreationForm form;
  String get fid => form.fid;
  String get formhash => form.formhash;
  Set<String> get allowedTypeIds => form.types.map((type) => type.id).toSet();
  bool? get typeRequired => form.typeRequired;
  int? get maxSubjectLength => form.maximumSubjectLength;
  int? get maxMessageLength => form.maximumMessageLength;

  @override
  String toString() => '_DiscuzThreadCreationToken(redacted)';
}

final class _DiscuzThreadReplyToken implements ThreadReplyPreparationToken {
  const _DiscuzThreadReplyToken({
    required this.owner,
    required this.target,
    required this.formhash,
    required this.hiddenFields,
    required this.referer,
  });

  final DiscuzThreadReplyAdapter owner;
  final ThreadReplyTarget target;
  final String formhash;
  final Map<String, String> hiddenFields;
  final Uri referer;

  @override
  String toString() => '_DiscuzThreadReplyToken(redacted)';
}

String _messageCode(DiscuzApiEnvelope envelope) =>
    _text(envelope.message?['messageval']);

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const <String, Object?>{};

String _text(Object? value) => value?.toString().trim() ?? '';

int? _int(Object? value) => int.tryParse(_text(value));

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value.trim());

bool _validPositiveUnique(Iterable<String> values) {
  final seen = <String>{};
  for (final raw in values) {
    if (raw.trim() != raw || !_positive(raw) || !seen.add(raw)) return false;
  }
  return true;
}

bool _validTarget(ThreadReplyTarget target) =>
    _positive(target.fid) &&
    _positive(target.tid) &&
    (target.kind == ThreadReplyTargetKind.thread ||
        _positive(target.pid ?? ''));

bool _sameTarget(ThreadReplyTarget left, ThreadReplyTarget right) =>
    left.kind == right.kind &&
    left.fid.trim() == right.fid.trim() &&
    left.tid.trim() == right.tid.trim() &&
    (left.pid?.trim() ?? '') == (right.pid?.trim() ?? '');

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port &&
    left.scheme.toLowerCase() == 'https';

List<String> _queryValues(Uri uri, String name) =>
    uri.queryParametersAll[name] ?? const <String>[];

String? _singleQuery(Uri uri, String name) {
  final values = _queryValues(uri, name);
  return values.length == 1 ? values.single.trim() : null;
}

String _clean(String source) =>
    source.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

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

DataCommandNotSent<T> _formhashNotSent<T>(ForumTransportFailure failure) =>
    DataCommandNotSent(
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
      ),
    );

DataCommandOutcomeUnknown<T> _outcomeUnknown<T>(String code) =>
    DataCommandOutcomeUnknown(
      DataCommandFailure(
        kind: DataCommandFailureKind.parse,
        retryPolicy: DataCommandRetryPolicy.explicitOnly,
        code: code,
        diagnosticMessage: code,
      ),
    );

DataCommandFailure _commandRejectedFailure(String code) {
  final normalized = _normalizeDiscuzMessageCode(code);
  final kind = switch (normalized.base) {
    _ when normalized.loginRequired => DataCommandFailureKind.unauthenticated,
    _ when normalized.base.contains('formhash') =>
      DataCommandFailureKind.staleFormhash,
    'postperm_login_nopermission' ||
    'postperm_login_nopermission_mobile' ||
    'replyperm_login_nopermission' => DataCommandFailureKind.unauthenticated,
    'postperm_none_nopermission' ||
    'replyperm_none_nopermission' ||
    'post_forum_newthread_nopermission' ||
    'post_forum_newreply_nopermission' ||
    'postperm_qqonly_nopermission' ||
    'trade_newreply_nopermission' => DataCommandFailureKind.permissionDenied,
    'post_subject_toolong' ||
    'post_subject_tooshort' ||
    'post_message_toolong' ||
    'post_message_tooshort' ||
    'post_sm_isnull' ||
    'emptymessage' ||
    'post_type_isnull' ||
    'post_pollinvalid' ||
    'pollinvalid' ||
    'polloption_count_invalid' ||
    'post_polloption_invalid' ||
    'post_polltype_isnull' => DataCommandFailureKind.validation,
    _ => DataCommandFailureKind.unknown,
  };
  return DataCommandFailure(
    kind: kind,
    retryPolicy: switch (kind) {
      DataCommandFailureKind.staleFormhash ||
      DataCommandFailureKind.unauthenticated =>
        DataCommandRetryPolicy.afterSessionRefresh,
      DataCommandFailureKind.validation =>
        DataCommandRetryPolicy.afterInputChange,
      _ => DataCommandRetryPolicy.explicitOnly,
    },
    code: code,
    diagnosticMessage: code,
  );
}

({String base, bool loginRequired}) _normalizeDiscuzMessageCode(String code) {
  var normalized = code.trim().toLowerCase();
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

DataCommandFailure _commandTransportFailure(
  ForumTransportFailure failure,
) => DataCommandFailure(
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
  retryPolicy: DataCommandRetryPolicy.explicitOnly,
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

final _creationCapabilities = ThreadCreationCapabilities(
  values: DataCapabilitySet.supported(ThreadCreationCapability.values),
);

final _replyCapabilities = ThreadReplyCapabilities(
  values: DataCapabilitySet.supported(ThreadReplyCapability.values),
);
