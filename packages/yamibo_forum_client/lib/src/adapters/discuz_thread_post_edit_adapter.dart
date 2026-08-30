import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_post_edit.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';

/// Experimental Discuz HTML adapter for ordinary post and reply editing.
final class DiscuzThreadPostEditAdapter
    implements ThreadPostEditPreparationRepository, ThreadPostEditCommand {
  /// Creates an adapter on the Host's shared transport.
  const DiscuzThreadPostEditAdapter({
    required this.config,
    required this.network,
    required this.requestProfiles,
  });

  /// Managed forum origins and request identities.
  final ForumClientConfig config;

  /// Shared Cookie/WAF-aware transport.
  final ForumClientNetwork network;

  /// Mobile/desktop request identity resolver.
  final ForumRequestProfileResolver requestProfiles;

  @override
  ThreadPostEditCapabilities get capabilities => _capabilities;

  @override
  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  load(ThreadPostEditPreparationRequest request) => _load(request);

  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  _load(ThreadPostEditPreparationRequest request) async {
    final validation = _validateTarget(request.target);
    if (validation != null) return _readFailure(validation);
    if (request.cancellation?.isCancelled ?? false) {
      return _cancelledRead();
    }
    final profileKind = _profileFor(request.target.formUri);
    if (profileKind == null) {
      return _readFailure('post_edit_display_mode_invalid');
    }
    final referer = _safeReferer(request.referer, request.target.formUri);
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: request.target.formUri,
        context: const ForumRequestContext(
          operation: 'thread.post_edit.form',
          pageKind: 'thread.post_edit',
        ),
        headers: requestProfiles.resolve(profileKind, referer: referer).headers,
        responseType: ForumResponseType.text,
        cancellation: request.cancellation,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _transportReadFailure(failure);
    }
    final documentResponse =
        (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (!_sameManagedAuthority(documentResponse.uri) ||
        _isHttpsDowngrade(request.target.formUri, documentResponse.uri)) {
      return _readFailure('post_edit_response_uri_invalid');
    }
    final body = documentResponse.body;
    if (body is! String) {
      return _readFailure('post_edit_response_not_text');
    }
    return _parsePreparation(
      body,
      target: request.target,
      sourceUri: documentResponse.uri,
      profileKind: profileKind,
      referer: referer,
    );
  }

  @override
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _DiscuzThreadPostEditToken || token.owner != this) {
      return _notSent('post_edit_preparation_owner_mismatch');
    }
    if (preparation.target != token.target ||
        preparation.revision != token.revision) {
      return _notSent('post_edit_preparation_identity_mismatch');
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _cancelledNotSent();
    }
    final message = submission.message;
    final subject = preparation.target.isFirstPost
        ? submission.subject.trim()
        : token.subject;
    if (message.trim().isEmpty ||
        (preparation.target.isFirstPost && subject.isEmpty)) {
      return _notSent('post_edit_content_required');
    }
    final newAids = _validatedAids(submission.newImageAttachmentIds);
    final removedAids = _validatedAids(submission.removedImageAttachmentIds);
    if (newAids == null || removedAids == null) {
      return _notSent('post_edit_attachment_identity_invalid');
    }
    if (newAids.toSet().intersection(removedAids.toSet()).isNotEmpty) {
      return _notSent('post_edit_attachment_state_conflict');
    }
    final existingAids = token.images.map((image) => image.aid).toSet();
    if (!existingAids.containsAll(removedAids)) {
      return _notSent('post_edit_removed_attachment_not_prepared');
    }
    final fields = _buildSubmissionFields(
      token,
      subject: subject,
      message: message,
      useSignature: submission.useSignature,
      newAids: newAids,
      removedAids: removedAids.toSet(),
    );
    if (fields == null) {
      return _notSent('post_edit_preparation_contract_changed');
    }
    final submitUri = _submitUri(token.submitUri);
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.post,
        uri: submitUri,
        context: const ForumRequestContext(
          operation: 'thread.post_edit.submit',
          pageKind: 'thread.post_edit',
          silent: true,
        ),
        headers: <String, String>{
          ...requestProfiles
              .resolve(token.profileKind, referer: token.sourceUri)
              .headers,
          'Accept': 'text/xml,text/plain,*/*',
        },
        body: ForumMultipartFields(fields),
        responseType: ForumResponseType.text,
        cancellation: submission.cancellation,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _confirmAfterAmbiguous(
        submission,
        token,
        subject: subject,
        message: message,
        newAids: newAids,
        removedAids: removedAids,
        originalFailure: _commandTransportFailure(failure),
      );
    }
    final submitResponse =
        (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
    final body = submitResponse.body;
    if (body is! String) {
      return _confirmAfterAmbiguous(
        submission,
        token,
        subject: subject,
        message: message,
        newAids: newAids,
        removedAids: removedAids,
        originalFailure: _commandFailure(
          DataCommandFailureKind.parse,
          'post_edit_response_not_text',
        ),
      );
    }
    final callback = _parseSubmitCallback(body, token.target);
    switch (callback) {
      case _EditSubmitApplied(:final pendingModeration):
        return DataCommandApplied(
          ThreadPostEditReceipt(
            target: token.target,
            publicationState: pendingModeration
                ? ThreadPostEditPublicationState.pendingModeration
                : ThreadPostEditPublicationState.published,
            confirmation: ThreadPostEditConfirmation.serverCallback,
          ),
        );
      case _EditSubmitRejected(:final code):
        return DataCommandRejected(_rejectedFailure(code));
      case _EditSubmitUnproved(:final code):
        return _confirmAfterAmbiguous(
          submission,
          token,
          subject: subject,
          message: message,
          newAids: newAids,
          removedAids: removedAids,
          originalFailure: _commandFailure(DataCommandFailureKind.parse, code),
        );
    }
  }

  Future<DataCommandResult<ThreadPostEditReceipt>> _confirmAfterAmbiguous(
    ThreadPostEditSubmission submission,
    _DiscuzThreadPostEditToken token, {
    required String subject,
    required String message,
    required List<String> newAids,
    required List<String> removedAids,
    required DataCommandFailure originalFailure,
  }) async {
    if (submission.cancellation?.isCancelled ?? false) {
      return DataCommandOutcomeUnknown(originalFailure);
    }
    final readback = await _load(
      ThreadPostEditPreparationRequest(
        target: token.target,
        referer: token.sourceUri,
        cancellation: submission.cancellation,
      ),
    );
    if (readback
        is! DataReadSuccess<
          ThreadPostEditPreparation,
          ThreadPostEditCapabilities
        >) {
      return DataCommandOutcomeUnknown(originalFailure);
    }
    final data = readback.data;
    if (data.revision == token.revision) {
      return DataCommandOutcomeUnknown(
        _commandFailure(
          DataCommandFailureKind.unknown,
          'post_edit_readback_unchanged',
        ),
      );
    }
    final contentMatches =
        _canonicalMessage(data.message) == _canonicalMessage(message) &&
        (!token.target.isFirstPost || data.subject.trim() == subject.trim());
    final returnedAids = data.existingImages.map((image) => image.aid).toSet();
    final expectedAids = <String>{
      ...token.images.map((image) => image.aid),
      ...newAids,
    }..removeAll(removedAids);
    final attachmentsMatch =
        returnedAids.containsAll(expectedAids) &&
        removedAids.every((aid) => !returnedAids.contains(aid));
    if (contentMatches && attachmentsMatch) {
      return DataCommandApplied(
        ThreadPostEditReceipt(
          target: token.target,
          publicationState: ThreadPostEditPublicationState.published,
          confirmation: ThreadPostEditConfirmation.readback,
        ),
      );
    }
    final code = contentMatches
        ? 'post_edit_attachment_state_unconfirmed'
        : 'post_edit_readback_mismatch';
    return DataCommandOutcomeUnknown(
      _commandFailure(DataCommandFailureKind.unknown, code),
    );
  }

  DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>
  _parsePreparation(
    String source, {
    required ThreadPostEditTarget target,
    required Uri sourceUri,
    required ForumRequestProfileKind profileKind,
    required Uri referer,
  }) {
    final document = html_parser.parse(source);
    final pageFailure = _documentFailure(document, source);
    if (pageFailure != null) return pageFailure;
    final forms = document.querySelectorAll('form#postform');
    if (forms.length != 1) {
      return _readFailure(
        forms.isEmpty ? 'post_edit_form_missing' : 'post_edit_form_duplicate',
      );
    }
    final form = forms.single;
    if ((form.attributes['method'] ?? '').trim().toLowerCase() != 'post') {
      return _readFailure('post_edit_form_method_invalid');
    }
    final enctype = (form.attributes['enctype'] ?? '').trim().toLowerCase();
    if (!enctype.startsWith('multipart/form-data')) {
      return _readFailure('post_edit_form_enctype_invalid');
    }
    final action = form.attributes['action']?.trim() ?? '';
    final submitUri = action.isEmpty ? null : sourceUri.resolve(action);
    if (submitUri == null ||
        !_validSubmitUri(submitUri, target, profileKind: profileKind)) {
      return _readFailure('post_edit_submit_uri_invalid');
    }
    const critical = <String>[
      'formhash',
      'posttime',
      'fid',
      'tid',
      'pid',
      'page',
      'subject',
      'message',
    ];
    final criticalValues = <String, String>{};
    for (final name in critical) {
      final controls = _controlsByName(form, name);
      if (controls.length != 1) {
        return _readFailure(
          controls.isEmpty
              ? 'post_edit_critical_control_missing'
              : 'post_edit_critical_control_duplicate',
        );
      }
      criticalValues[name] = _controlValue(controls.single);
    }
    final messageControl = _controlsByName(form, 'message').single;
    if (messageControl.localName != 'textarea' ||
        messageControl.id != 'needmessage') {
      return _readFailure('post_edit_message_control_invalid');
    }
    if (criticalValues['formhash']!.trim().isEmpty ||
        criticalValues['posttime']!.trim().isEmpty ||
        criticalValues['fid'] != target.fid ||
        criticalValues['tid'] != target.tid ||
        criticalValues['pid'] != target.pid ||
        int.tryParse(criticalValues['page']!) != target.page) {
      return _readFailure('post_edit_form_identity_mismatch');
    }
    final extraction = _extractControls(form);
    if (extraction.unsupported || _hasExternalControls(document, form)) {
      return _unsupportedRead('post_edit_unknown_successful_control');
    }
    final unsupported = _unsupportedFormReason(
      document,
      form,
      extraction.fields,
    );
    if (unsupported != null) return _unsupportedRead(unsupported);
    final images = _parseImages(document, sourceUri);
    if (images == null) return _readFailure('post_edit_attachment_invalid');
    final subject = criticalValues['subject']!;
    final message = criticalValues['message']!;
    final useSignature =
        extraction.fields
            .where((field) => field.name.toLowerCase() == 'usesig')
            .map((field) => field.value.trim() == '1')
            .firstOrNull ??
        true;
    final revision = _fingerprint(
      target,
      subject,
      message,
      extraction.fields,
      images,
    );
    final token = _DiscuzThreadPostEditToken(
      owner: this,
      target: target,
      sourceUri: sourceUri,
      submitUri: submitUri,
      referer: referer,
      profileKind: profileKind,
      fields: extraction.fields,
      subject: subject,
      message: message,
      images: images,
      revision: revision,
    );
    return DataReadSuccess(
      data: ThreadPostEditPreparation(
        target: target,
        sourceUri: sourceUri,
        subject: subject,
        message: message,
        useSignature: useSignature,
        existingImages: List.unmodifiable(images),
        revision: revision,
        token: token,
      ),
      capabilities: _capabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  List<MapEntry<String, String>>? _buildSubmissionFields(
    _DiscuzThreadPostEditToken token, {
    required String subject,
    required String message,
    required bool useSignature,
    required List<String> newAids,
    required Set<String> removedAids,
  }) {
    final result = <MapEntry<String, String>>[];
    var subjectCount = 0;
    var messageCount = 0;
    var editSubmitWritten = false;
    for (final field in token.fields) {
      final name = field.name.trim();
      final lower = name.toLowerCase();
      final attachmentAid = _attachmentAid(name);
      if (_filteredField(lower) ||
          (attachmentAid != null && removedAids.contains(attachmentAid))) {
        continue;
      }
      if (!_allowedField(name)) return null;
      if (lower == 'subject') {
        subjectCount += 1;
        result.add(MapEntry(name, subject));
      } else if (lower == 'message') {
        messageCount += 1;
        result.add(MapEntry(name, message));
      } else if (lower == 'usesig') {
        continue;
      } else if (lower == 'editsubmit') {
        if (!editSubmitWritten) {
          editSubmitWritten = true;
          result.add(MapEntry(name, 'yes'));
        }
      } else {
        result.add(MapEntry(name, field.value));
      }
    }
    if (subjectCount != 1 || messageCount != 1) return null;
    if (!editSubmitWritten) result.add(const MapEntry('editsubmit', 'yes'));
    if (useSignature) result.add(const MapEntry('usesig', '1'));
    final existingAids = token.images.map((image) => image.aid).toSet();
    for (final aid in newAids) {
      if (!existingAids.contains(aid)) {
        result.add(MapEntry('attachnew[$aid][description]', ''));
      }
    }
    return List.unmodifiable(result);
  }

  _EditSubmitProof _parseSubmitCallback(
    String source,
    ThreadPostEditTarget target,
  ) {
    final payload = _cdata(source) ?? source;
    final errorCallbacks = RegExp(
      r'errorhandle_postform\s*\(',
      caseSensitive: false,
    ).allMatches(payload).length;
    final successCallbacks = RegExp(
      r'succeedhandle_postform\s*\(',
      caseSensitive: false,
    ).allMatches(payload).length;
    if (errorCallbacks > 0) {
      if (errorCallbacks != 1 || successCallbacks != 0) {
        return const _EditSubmitUnproved('post_edit_callback_ambiguous');
      }
      return _EditSubmitRejected(_discuzErrorCode(payload));
    }
    if (successCallbacks != 1) {
      return const _EditSubmitUnproved('post_edit_success_callback_missing');
    }
    final fid = _callbackIdentity(payload, 'fid');
    final tid = _callbackIdentity(payload, 'tid');
    final pid = _callbackIdentity(payload, 'pid');
    if (fid != target.fid || tid != target.tid || pid != target.pid) {
      return const _EditSubmitUnproved('post_edit_callback_identity_mismatch');
    }
    final uriMatch = RegExp(
      r'''succeedhandle_postform\s*\(\s*(['"])(.*?)\1\s*,''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(payload);
    final rawUri = uriMatch?.group(2)?.replaceAll(r'\/', '/') ?? '';
    final callbackUri = rawUri.isEmpty ? null : target.formUri.resolve(rawUri);
    if (callbackUri == null ||
        !_sameManagedAuthority(callbackUri) ||
        _isHttpsDowngrade(target.formUri, callbackUri) ||
        !_callbackUriMatchesTarget(callbackUri, target)) {
      return const _EditSubmitUnproved('post_edit_callback_uri_invalid');
    }
    final lower = payload.toLowerCase();
    return _EditSubmitApplied(
      pendingModeration:
          lower.contains('edit_newthread_mod_succeed') ||
          lower.contains('edit_reply_mod_succeed') ||
          lower.contains('audit_edit_succeed'),
    );
  }

  DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>?
  _documentFailure(html_dom.Document document, String source) {
    final normalized =
        '${document.querySelector('title')?.text ?? ''} '
                '${document.body?.text ?? ''} $source'
            .toLowerCase();
    if (document.querySelector('form#loginform, .loginbox') != null ||
        normalized.contains('请先登录') ||
        normalized.contains('login required')) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'post_edit_authentication_required',
        diagnosticMessage: 'post_edit_authentication_required',
      );
    }
    final code = _knownEditError(normalized);
    if (code == null) return null;
    return DataReadFailure(
      kind: code == 'post_edit_nopermission'
          ? DataReadFailureKind.unauthorized
          : DataReadFailureKind.business,
      code: code,
      diagnosticMessage: code,
    );
  }

  String _discuzErrorCode(String payload) =>
      _knownEditError(payload.toLowerCase()) ?? 'post_edit_rejected';

  String? _knownEditError(String source) {
    const directCodes = <String>[
      'submit_invalid',
      'post_edit_nopermission',
      'post_edit_timelimit',
      'post_nonexistence',
      'thread_nonexistence',
      'post_thread_closed',
      'post_sm_isnull',
      'post_subject_tooshort',
      'post_subject_toolong',
      'post_message_tooshort',
      'post_message_toolong',
      'post_hide_nopermission',
    ];
    for (final code in directCodes) {
      if (source.contains(code)) return code;
    }
    if (source.contains('formhash') &&
        (source.contains('无效') ||
            source.contains('过期') ||
            source.contains('invalid') ||
            source.contains('expired'))) {
      return 'submit_invalid';
    }
    if (source.contains('编辑时间') && source.contains('超过')) {
      return 'post_edit_timelimit';
    }
    if (source.contains('无权编辑') ||
        source.contains('没有权限编辑') ||
        source.contains('permission denied')) {
      return 'post_edit_nopermission';
    }
    if (source.contains('回复不存在') || source.contains('帖子不存在')) {
      return 'post_nonexistence';
    }
    if (source.contains('主题不存在')) return 'thread_nonexistence';
    if (source.contains('主题已关闭') || source.contains('帖子已关闭')) {
      return 'post_thread_closed';
    }
    if (source.contains('标题') && source.contains('太短')) {
      return 'post_subject_tooshort';
    }
    if (source.contains('标题') && source.contains('太长')) {
      return 'post_subject_toolong';
    }
    if ((source.contains('内容') || source.contains('消息')) &&
        source.contains('太短')) {
      return 'post_message_tooshort';
    }
    if ((source.contains('内容') || source.contains('消息')) &&
        source.contains('太长')) {
      return 'post_message_toolong';
    }
    return null;
  }

  _ControlExtraction _extractControls(html_dom.Element form) {
    final fields = <_EditField>[];
    var unsupported = false;
    for (final control in form.querySelectorAll('input, textarea, select')) {
      final name = control.attributes['name']?.trim() ?? '';
      if (name.isEmpty || _disabled(control)) continue;
      if (control.localName == 'textarea') {
        fields.add(_EditField(name, control.text));
      } else if (control.localName == 'select') {
        final options = control
            .querySelectorAll('option')
            .where((option) => !_disabled(option))
            .toList(growable: false);
        final selected = options
            .where((option) => option.attributes.containsKey('selected'))
            .toList(growable: false);
        final values = selected.isNotEmpty
            ? selected
            : control.attributes.containsKey('multiple') || options.isEmpty
            ? const <html_dom.Element>[]
            : <html_dom.Element>[options.first];
        if (options.isEmpty && !control.attributes.containsKey('multiple')) {
          unsupported = true;
        }
        for (final option in values) {
          fields.add(
            _EditField(name, option.attributes['value'] ?? option.text),
          );
        }
      } else {
        final type = (control.attributes['type'] ?? 'text').toLowerCase();
        if (const <String>{
          'file',
          'submit',
          'button',
          'reset',
          'image',
        }.contains(type)) {
          continue;
        }
        if (type == 'checkbox' || type == 'radio') {
          if (control.attributes.containsKey('checked')) {
            fields.add(_EditField(name, control.attributes['value'] ?? 'on'));
          }
        } else if (const <String>{
          'hidden',
          'text',
          'search',
          'tel',
          'url',
          'email',
          'password',
          'number',
        }.contains(type)) {
          fields.add(_EditField(name, control.attributes['value'] ?? ''));
        } else {
          unsupported = true;
        }
      }
    }
    return _ControlExtraction(List.unmodifiable(fields), unsupported);
  }

  String? _unsupportedFormReason(
    html_dom.Document document,
    html_dom.Element form,
    List<_EditField> fields,
  ) {
    if (document.querySelectorAll('#attlist li').isNotEmpty) {
      return 'post_edit_regular_attachment_unsupported';
    }
    for (final control in form.querySelectorAll(
      '[name], [data-plugin], [id]',
    )) {
      final name = (control.attributes['name'] ?? '').trim().toLowerCase();
      final id = (control.attributes['id'] ?? '').trim().toLowerCase();
      final value = _controlValue(control).trim();
      if ((name == 'special' && value != '0') ||
          name == 'specialextra' ||
          name.startsWith('poll') ||
          name.startsWith('trade') ||
          name.startsWith('reward') ||
          name.startsWith('activity') ||
          name.startsWith('debate') ||
          name.startsWith('rushreply') ||
          name.startsWith('replycredit') ||
          name.startsWith('cronpublish')) {
        return 'post_edit_special_thread_unsupported';
      }
      if ((name == 'sortid' && value != '0') ||
          name.startsWith('typeoption[')) {
        return 'post_edit_thread_sort_unsupported';
      }
      if (name.contains('plugin') ||
          name.startsWith('ext_') ||
          id.contains('plugin') ||
          control.attributes.containsKey('data-plugin')) {
        return 'post_edit_plugin_field_unsupported';
      }
      if (name == 'delete' ||
          name == 'delattachop' ||
          name.startsWith('delete[') ||
          name.startsWith('delattachop[') ||
          name == 'audit' ||
          name.startsWith('audit[')) {
        return 'post_edit_destructive_control_unsupported';
      }
    }
    for (final field in fields) {
      final lower = field.name.toLowerCase();
      if ((lower == 'htmlon' ||
              lower == 'bbcodeoff' ||
              lower == 'imgcontent') &&
          field.value.trim() == '1') {
        return 'post_edit_html_mode_unsupported';
      }
      if (!_allowedField(field.name)) {
        return 'post_edit_unknown_successful_control';
      }
    }
    return null;
  }

  List<ThreadPostEditImageAttachment>? _parseImages(
    html_dom.Document document,
    Uri sourceUri,
  ) {
    final images = <ThreadPostEditImageAttachment>[];
    final seen = <String>{};
    for (final marker in document.querySelectorAll('#imglist [aid]')) {
      final aid = marker.attributes['aid']?.trim() ?? '';
      if (!_positive(aid) || !seen.add(aid)) return null;
      final item = _nearest(marker, 'li') ?? marker;
      final image = item.querySelector('img[src]');
      final src = image?.attributes['src']?.trim() ?? '';
      final uri = src.isEmpty ? null : sourceUri.resolve(src);
      if (uri == null ||
          !_sameManagedAuthority(uri) ||
          _isHttpsDowngrade(sourceUri, uri)) {
        return null;
      }
      var description = '';
      for (final input in item.querySelectorAll('input[name]')) {
        final name = input.attributes['name'] ?? '';
        if (name.contains('attachnew[$aid]') &&
            name.toLowerCase().contains('description')) {
          description = input.attributes['value'] ?? '';
          break;
        }
      }
      images.add(
        ThreadPostEditImageAttachment(
          aid: aid,
          imageUri: uri,
          isAssociated: marker.attributes['up'] == '1',
          description: description,
          fileName: image?.attributes['alt'],
        ),
      );
    }
    return List.unmodifiable(images);
  }

  String? _validateTarget(ThreadPostEditTarget target) {
    if (!_positive(target.fid) ||
        !_positive(target.tid) ||
        !_positive(target.pid) ||
        target.page < 1 ||
        !_sameManagedAuthority(target.formUri) ||
        target.formUri.userInfo.isNotEmpty ||
        target.formUri.path.toLowerCase() != '/forum.php') {
      return 'post_edit_target_invalid';
    }
    final query = target.formUri.queryParametersAll;
    if (_single(query, 'mod')?.toLowerCase() != 'post' ||
        _single(query, 'action')?.toLowerCase() != 'edit') {
      return 'post_edit_target_action_invalid';
    }
    final identities = <String, String>{
      'fid': target.fid,
      'tid': target.tid,
      'pid': target.pid,
      'page': target.page.toString(),
    };
    for (final entry in identities.entries) {
      final value = _single(query, entry.key);
      if (value != null && value != entry.value) {
        return 'post_edit_target_identity_mismatch';
      }
      final values = query[entry.key];
      if (values != null && values.length != 1) {
        return 'post_edit_target_query_duplicate';
      }
    }
    return null;
  }

  ForumRequestProfileKind? _profileFor(Uri uri) {
    final values = uri.queryParametersAll['mobile'];
    if (values == null) return ForumRequestProfileKind.desktopHtml;
    if (values.length != 1) return null;
    return switch (values.single.trim().toLowerCase()) {
      '2' => ForumRequestProfileKind.mobileHtml,
      'no' => ForumRequestProfileKind.desktopHtml,
      _ => null,
    };
  }

  Uri _safeReferer(Uri? candidate, Uri fallback) {
    if (candidate == null ||
        !_sameManagedAuthority(candidate) ||
        candidate.userInfo.isNotEmpty ||
        _isHttpsDowngrade(fallback, candidate)) {
      return fallback;
    }
    return candidate.replace(fragment: '');
  }

  bool _validSubmitUri(
    Uri uri,
    ThreadPostEditTarget target, {
    required ForumRequestProfileKind profileKind,
  }) {
    if (!_sameManagedAuthority(uri) ||
        uri.userInfo.isNotEmpty ||
        uri.path.toLowerCase() != '/forum.php' ||
        _isHttpsDowngrade(target.formUri, uri)) {
      return false;
    }
    final query = uri.queryParametersAll;
    if (_single(query, 'mod')?.toLowerCase() != 'post' ||
        _single(query, 'action')?.toLowerCase() != 'edit' ||
        _single(query, 'editsubmit')?.toLowerCase() != 'yes' ||
        _profileFor(uri) != profileKind) {
      return false;
    }
    final identities = <String, String>{
      'fid': target.fid,
      'tid': target.tid,
      'pid': target.pid,
      'page': target.page.toString(),
    };
    for (final entry in identities.entries) {
      final values = query[entry.key];
      if (values != null &&
          (values.length != 1 || values.single != entry.value)) {
        return false;
      }
    }
    return true;
  }

  Uri _submitUri(Uri uri) => uri.replace(
    queryParameters: <String, String>{
      for (final entry in uri.queryParameters.entries)
        if (entry.key.toLowerCase() != 'formhash') entry.key: entry.value,
      'editsubmit': 'yes',
      'inajax': '1',
      'handlekey': 'postform',
    },
    fragment: '',
  );

  bool _callbackUriMatchesTarget(Uri uri, ThreadPostEditTarget target) {
    if (uri.path.toLowerCase() != '/forum.php') return false;
    final query = uri.queryParameters;
    if (query['mod'] == 'viewthread') {
      return query['tid'] == target.tid &&
          (query['pid'] == null || query['pid'] == target.pid);
    }
    return query['mod'] == 'redirect' &&
        query['goto'] == 'findpost' &&
        query['ptid'] == target.tid &&
        query['pid'] == target.pid;
  }

  bool _sameManagedAuthority(Uri uri) {
    bool same(Uri origin) =>
        uri.scheme.toLowerCase() == origin.scheme.toLowerCase() &&
        uri.host.toLowerCase() == origin.host.toLowerCase() &&
        uri.port == origin.port;
    return same(config.siteOrigin) ||
        (config.apiOrigin != null && same(config.apiOrigin!));
  }

  bool _isHttpsDowngrade(Uri from, Uri to) =>
      from.scheme.toLowerCase() == 'https' &&
      to.scheme.toLowerCase() != 'https';

  bool _hasExternalControls(
    html_dom.Document document,
    html_dom.Element form,
  ) => document
      .querySelectorAll('input, textarea, select')
      .any(
        (control) =>
            !form.contains(control) &&
            control.attributes['form'] == 'postform' &&
            (control.attributes['name']?.trim().isNotEmpty ?? false),
      );

  List<html_dom.Element> _controlsByName(html_dom.Element form, String name) =>
      form
          .querySelectorAll('input, textarea, select')
          .where((control) => control.attributes['name'] == name)
          .toList(growable: false);

  String _controlValue(html_dom.Element control) =>
      control.localName == 'textarea'
      ? control.text
      : control.attributes['value'] ?? '';

  bool _disabled(html_dom.Element element) {
    if (element.attributes.containsKey('disabled')) return true;
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == 'fieldset' &&
          parent.attributes.containsKey('disabled')) {
        final legend = parent.querySelector('legend');
        if (legend == null || !_descendantOf(element, legend)) return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  bool _descendantOf(html_dom.Element element, html_dom.Element ancestor) {
    var parent = element.parent;
    while (parent != null) {
      if (parent == ancestor) return true;
      parent = parent.parent;
    }
    return false;
  }

  html_dom.Element? _nearest(html_dom.Element element, String localName) {
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == localName) return parent;
      parent = parent.parent;
    }
    return null;
  }

  bool _allowedField(String name) {
    final lower = name.toLowerCase();
    if (_allowedFields.contains(lower)) return true;
    return _attachmentAid(name) != null;
  }

  String? _attachmentAid(String name) {
    final match = RegExp(
      r'^(attachnew|attachupdate)\[([1-9]\d*)\]\[([^\]]+)\]$',
      caseSensitive: false,
    ).firstMatch(name.trim());
    if (match == null) return null;
    final key = match.group(3)!.replaceAll("'", '').replaceAll('"', '');
    return const <String>{'description', 'readperm', 'price'}.contains(key)
        ? match.group(2)
        : null;
  }

  bool _filteredField(String lower) =>
      lower == 'delete' ||
      lower.startsWith('delete[') ||
      lower == 'delattachop' ||
      lower.startsWith('delattachop[') ||
      lower == 'filedata' ||
      lower.startsWith('filedata[');

  List<String>? _validatedAids(Iterable<String> source) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in source) {
      final aid = raw.trim();
      if (!_positive(aid) || !seen.add(aid)) return null;
      result.add(aid);
    }
    return List.unmodifiable(result);
  }

  String _fingerprint(
    ThreadPostEditTarget target,
    String subject,
    String message,
    List<_EditField> fields,
    List<ThreadPostEditImageAttachment> images,
  ) {
    final payload = jsonEncode(<String, Object?>{
      'target': <String>[target.fid, target.tid, target.pid],
      'subject': _normalizeText(subject),
      'message': _normalizeText(message),
      'fields': fields
          .where((field) => !_volatileFields.contains(field.name.toLowerCase()))
          .map((field) => <String>[field.name, _normalizeText(field.value)])
          .toList(growable: false),
      'images': images
          .map(
            (image) => <Object?>[
              image.aid,
              image.imageUri.toString(),
              image.isAssociated,
              image.description,
              image.fileName,
            ],
          )
          .toList(growable: false),
    });
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(payload)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _canonicalMessage(String value) {
    final normalized = _normalizeText(value);
    return normalized.replaceAllMapped(
      RegExp(
        r'\[(?:attach|attachimg)\]\s*([1-9]\d*)\s*\[\/(?:attach|attachimg)\]',
        caseSensitive: false,
      ),
      (match) => '[attach]${match.group(1)}[/attach]',
    );
  }

  String _normalizeText(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  String? _callbackIdentity(String payload, String name) {
    final matches = RegExp(
      '''['"]${RegExp.escape(name)}['"]\\s*:\\s*['"]([1-9]\\d*)['"]''',
      caseSensitive: false,
    ).allMatches(payload).map((match) => match.group(1)!).toSet();
    return matches.length == 1 ? matches.single : null;
  }

  String? _cdata(String source) {
    final match = RegExp(
      r'<!\[CDATA\[([\s\S]*?)\]\]>',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1);
  }

  String? _single(Map<String, List<String>> values, String name) {
    final entries = values[name];
    if (entries == null || entries.length != 1) return null;
    final value = entries.single.trim();
    return value.isEmpty ? null : value;
  }

  bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);
}

final class _DiscuzThreadPostEditToken
    implements ThreadPostEditPreparationToken {
  const _DiscuzThreadPostEditToken({
    required this.owner,
    required this.target,
    required this.sourceUri,
    required this.submitUri,
    required this.referer,
    required this.profileKind,
    required this.fields,
    required this.subject,
    required this.message,
    required this.images,
    required this.revision,
  });

  final DiscuzThreadPostEditAdapter owner;
  final ThreadPostEditTarget target;
  final Uri sourceUri;
  final Uri submitUri;
  final Uri referer;
  final ForumRequestProfileKind profileKind;
  final List<_EditField> fields;
  final String subject;
  final String message;
  final List<ThreadPostEditImageAttachment> images;
  final String revision;
}

final class _EditField {
  const _EditField(this.name, this.value);
  final String name;
  final String value;
}

final class _ControlExtraction {
  const _ControlExtraction(this.fields, this.unsupported);
  final List<_EditField> fields;
  final bool unsupported;
}

sealed class _EditSubmitProof {
  const _EditSubmitProof();
}

final class _EditSubmitApplied extends _EditSubmitProof {
  const _EditSubmitApplied({required this.pendingModeration});
  final bool pendingModeration;
}

final class _EditSubmitRejected extends _EditSubmitProof {
  const _EditSubmitRejected(this.code);
  final String code;
}

final class _EditSubmitUnproved extends _EditSubmitProof {
  const _EditSubmitUnproved(this.code);
  final String code;
}

DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
_readFailure(String code) => DataReadFailure(
  kind: DataReadFailureKind.parse,
  code: code,
  diagnosticMessage: code,
);

DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
_unsupportedRead(String code) => DataReadFailure(
  kind: DataReadFailureKind.unsupported,
  code: code,
  diagnosticMessage: code,
);

DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
_cancelledRead() => const DataReadFailure(
  kind: DataReadFailureKind.cancelled,
  code: 'request_cancelled',
  diagnosticMessage: 'request_cancelled',
);

DataReadFailure<ThreadPostEditPreparation, ThreadPostEditCapabilities>
_transportReadFailure(ForumTransportFailure failure) => DataReadFailure(
  kind: toReadFailureKind(failure.kind),
  code: failure.code,
  statusCode: failure.statusCode,
  diagnosticMessage: failure.code,
);

DataCommandNotSent<ThreadPostEditReceipt> _notSent(String code) =>
    DataCommandNotSent(
      DataCommandFailure(
        kind: DataCommandFailureKind.validation,
        retryPolicy: DataCommandRetryPolicy.afterInputChange,
        code: code,
        diagnosticMessage: code,
      ),
    );

DataCommandNotSent<ThreadPostEditReceipt> _cancelledNotSent() =>
    const DataCommandNotSent(
      DataCommandFailure(
        kind: DataCommandFailureKind.cancelled,
        retryPolicy: DataCommandRetryPolicy.never,
        code: 'request_cancelled',
        diagnosticMessage: 'request_cancelled',
      ),
    );

DataCommandFailure _commandFailure(DataCommandFailureKind kind, String code) =>
    DataCommandFailure(
      kind: kind,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: code,
      diagnosticMessage: code,
    );

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

DataCommandFailure _rejectedFailure(String code) {
  final kind = switch (code) {
    'submit_invalid' => DataCommandFailureKind.staleFormhash,
    'post_edit_nopermission' => DataCommandFailureKind.permissionDenied,
    'post_subject_tooshort' ||
    'post_subject_toolong' ||
    'post_message_tooshort' ||
    'post_message_toolong' ||
    'post_sm_isnull' => DataCommandFailureKind.validation,
    _ => DataCommandFailureKind.unknown,
  };
  return DataCommandFailure(
    kind: kind,
    retryPolicy: switch (kind) {
      DataCommandFailureKind.staleFormhash =>
        DataCommandRetryPolicy.afterSessionRefresh,
      DataCommandFailureKind.validation =>
        DataCommandRetryPolicy.afterInputChange,
      _ => DataCommandRetryPolicy.explicitOnly,
    },
    code: code,
    diagnosticMessage: code,
  );
}

const Set<String> _allowedFields = <String>{
  'formhash',
  'posttime',
  'fid',
  'tid',
  'pid',
  'page',
  'subject',
  'message',
  'editsubmit',
  'typeid',
  'readperm',
  'price',
  'tags',
  'isanonymous',
  'hiddenreplies',
  'ordertype',
  'allownoticeauthor',
  'usesig',
  'parseurloff',
  'smileyoff',
  'bbcodeoff',
  'htmlon',
  'imgcontent',
};

const Set<String> _volatileFields = <String>{
  'formhash',
  'posttime',
  'editsubmit',
  'handlekey',
  'inajax',
  'geoloc',
};

final _capabilities = ThreadPostEditCapabilities(
  values: DataCapabilitySet.supported(ThreadPostEditCapability.values),
);
