import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../contracts/data_read_contract.dart';
import '../contracts/thread_composer_commands.dart';
import '../contracts/thread_read_access.dart';
import 'discuz_read_access_parser.dart';

/// Structured refusal to prepare a form for native submission.
final class DiscuzCreationFormFailure implements Exception {
  /// Creates a safe diagnostic code and failure category.
  const DiscuzCreationFormFailure(this.code, this.kind);

  /// Safe protocol diagnostic, without server body or credentials.
  final String code;

  /// Category the host can map to recovery UI.
  final DataReadFailureKind kind;
}

/// Validated identity, credentials and capabilities from a mobile post form.
final class DiscuzThreadCreationForm {
  /// Creates a parsed form bound to a forum and topic kind.
  const DiscuzThreadCreationForm({
    required this.fid,
    required this.kind,
    required this.sourceUri,
    required this.formhash,
    required this.posttime,
    required this.types,
    required this.typeRequired,
    required this.readAccess,
    this.maximumSubjectLength,
    this.maximumMessageLength,
    this.pollConstraints,
  });

  /// Validated destination forum.
  final String fid;

  /// Topic kind proved by the form.
  final ThreadCreationKind kind;

  /// Validated HTML URL used as submission referer.
  final Uri sourceUri;

  /// Form credential retained only in the opaque preparation token.
  final String formhash;

  /// Server-issued timestamp submitted with the form.
  final String posttime;

  /// Enabled classification choices.
  final List<ThreadCreationType> types;

  /// True only for an explicit requirement; null means undeclared.
  final bool? typeRequired;

  /// Topic permission capability and selection evidence.
  final ThreadReadAccess readAccess;

  /// Declared subject limit, or null when absent.
  final int? maximumSubjectLength;

  /// Declared message limit, or null when absent.
  final int? maximumMessageLength;

  /// Poll controls and limits, absent for ordinary topics.
  final ThreadPollConstraints? pollConstraints;
}

/// The supported mobile post template is a protocol boundary, not a browser.
final class DiscuzThreadCreationFormParser {
  /// Creates a parser that never executes template scripts.
  const DiscuzThreadCreationFormParser();

  /// Validates identity and supported controls before exposing form metadata.
  DiscuzThreadCreationForm parse(
    String source, {
    required Uri sourceUri,
    required Uri requestedUri,
    required String fid,
    required ThreadCreationKind kind,
  }) {
    if (!_sameOrigin(sourceUri, requestedUri) ||
        sourceUri.path != '/forum.php') {
      throw const FormatException('thread_creation_response_uri_invalid');
    }
    final sourceQuery = sourceUri.queryParametersAll;
    for (final entry in {
      'mod': 'post',
      'action': 'newthread',
      'fid': fid,
      'mobile': '2',
    }.entries) {
      if (sourceQuery[entry.key]?.length != 1 ||
          sourceQuery[entry.key]!.single != entry.value) {
        throw const FormatException(
          'thread_creation_response_identity_mismatch',
        );
      }
    }
    final document = html_parser.parse(source);
    if (document.querySelector('form#loginform, .loginbox') != null) {
      throw const DiscuzCreationFormFailure(
        'thread_creation_login_required',
        DataReadFailureKind.unauthorized,
      );
    }
    final forms = document.querySelectorAll('form#postform');
    if (forms.length != 1) {
      throw const DiscuzCreationFormFailure(
        'thread_creation_form_unavailable',
        DataReadFailureKind.business,
      );
    }
    final form = forms.single;
    if (document
            .querySelectorAll('[form="postform"]')
            .any((control) => !form.contains(control)) ||
        form
            .querySelectorAll('[form]')
            .any((control) => control.attributes['form'] != 'postform')) {
      throw const FormatException(
        'thread_creation_external_control_unsupported',
      );
    }
    if (form.attributes['method']?.toLowerCase() != 'post') {
      throw const FormatException('thread_creation_form_method_invalid');
    }
    final action = sourceUri.resolve(form.attributes['action'] ?? '');
    final query = action.queryParametersAll;
    String? one(String name) {
      final values = query[name];
      if (values == null) return null;
      if (values.length != 1) {
        throw const FormatException('thread_creation_duplicate_query');
      }
      return values.single;
    }

    if (!_sameOrigin(action, requestedUri) ||
        action.path != '/forum.php' ||
        one('mod') != 'post' ||
        one('action') != 'newthread' ||
        one('fid') != fid ||
        one('mobile') != '2' ||
        one('topicsubmit') != 'yes') {
      throw const FormatException('thread_creation_form_identity_mismatch');
    }
    final declaredFid = _field(form, 'fid', optional: true);
    if (declaredFid != null && declaredFid != fid) {
      throw const FormatException('thread_creation_form_identity_mismatch');
    }
    final special = _field(form, 'special', optional: true) ?? '0';
    if (special != (kind == ThreadCreationKind.poll ? '1' : '0')) {
      throw const FormatException('thread_creation_form_kind_mismatch');
    }
    for (final control in form.querySelectorAll('[name]')) {
      final name = control.attributes['name']!.toLowerCase();
      if (name.contains('seccode') ||
          name.contains('secanswer') ||
          name == 'specialextra' ||
          name.startsWith('typeoption[') ||
          (name == 'sortid' && (control.attributes['value'] ?? '0') != '0')) {
        throw const DiscuzCreationFormFailure(
          'thread_creation_form_unsupported',
          DataReadFailureKind.unsupported,
        );
      }
    }
    final formhash = _field(form, 'formhash')!;
    final posttime = _field(form, 'posttime')!;
    if (formhash.isEmpty || !RegExp(r'^[1-9]\d*$').hasMatch(posttime)) {
      throw const FormatException('thread_creation_credentials_missing');
    }
    final typeControls = form.querySelectorAll('select[name="typeid"]');
    if (typeControls.length > 1) {
      throw const FormatException('thread_creation_type_control_duplicate');
    }
    final typeControl = typeControls.singleOrNull;
    final types = <ThreadCreationType>[];
    final ids = <String>{};
    if (typeControl != null && !discuzControlDisabled(typeControl)) {
      for (final option in typeControl.querySelectorAll('option')) {
        if (discuzControlDisabled(option)) continue;
        final id = (option.attributes['value'] ?? '').trim();
        if (id.isEmpty || id == '0') continue;
        if (!RegExp(r'^[1-9]\d*$').hasMatch(id) || !ids.add(id)) {
          throw const FormatException('thread_creation_type_invalid');
        }
        types.add(ThreadCreationType(id: id, name: option.text.trim()));
      }
    }
    ThreadPollConstraints? pollConstraints;
    if (kind == ThreadCreationKind.poll) {
      for (final name in [
        'maxchoices',
        'expiration',
        'overt',
        'visibilitypoll',
      ]) {
        final controls = form.querySelectorAll('[name="$name"]');
        if (controls.length != 1 || discuzControlDisabled(controls.single)) {
          throw const FormatException('thread_creation_poll_control_missing');
        }
      }
      final option = form.querySelector('[name="polloption[]"]');
      if (option == null ||
          discuzControlDisabled(option) ||
          _field(form, 'polls') != 'yes') {
        throw const FormatException('thread_creation_poll_control_missing');
      }
      // Read only the numeric assignment emitted by post_poll.htm, never JS.
      final limits = <int>{};
      final assignment = RegExp(
        r'''\bvar\s+maxoptions\s*=\s*parseInt\(\s*['"](\d+)['"]\s*\)\s*;''',
      );
      for (final script in document.querySelectorAll('script')) {
        for (final match in assignment.allMatches(script.text)) {
          limits.add(int.parse(match.group(1)!));
        }
      }
      if (limits.length > 1 || (limits.isNotEmpty && limits.single < 2)) {
        throw const FormatException('thread_creation_poll_limit_invalid');
      }
      pollConstraints = ThreadPollConstraints(
        maximumOptions: limits.singleOrNull,
        maximumOptionLength: _maximumLength(option),
      );
    }
    final subject = form.querySelector('input[name="subject"]');
    final message = form.querySelector('textarea[name="message"]');
    if (subject == null ||
        message == null ||
        discuzControlDisabled(subject) ||
        discuzControlDisabled(message)) {
      throw const FormatException('thread_creation_content_control_missing');
    }
    return DiscuzThreadCreationForm(
      fid: fid,
      kind: kind,
      sourceUri: sourceUri,
      formhash: formhash,
      posttime: posttime,
      types: List.unmodifiable(types),
      typeRequired: typeControl?.attributes.containsKey('required') == true
          ? true
          : null,
      readAccess: const DiscuzReadAccessParser().parse(form, creating: true),
      maximumSubjectLength: _maximumLength(subject),
      maximumMessageLength: _maximumLength(message),
      pollConstraints: pollConstraints,
    );
  }

  String? _field(Element form, String name, {bool optional = false}) {
    final fields = form.querySelectorAll('input[name="$name"]');
    if (fields.isEmpty && optional) return null;
    if (fields.length != 1 || discuzControlDisabled(fields.single)) {
      throw const FormatException('thread_creation_field_missing_or_duplicate');
    }
    return fields.single.attributes['value']?.trim() ?? '';
  }

  int? _maximumLength(Element element) {
    final raw = element.attributes['maxlength'];
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      throw const FormatException('thread_creation_length_invalid');
    }
    return value;
  }

  bool _sameOrigin(Uri a, Uri b) =>
      a.userInfo.isEmpty &&
      a.scheme == b.scheme &&
      a.host == b.host &&
      a.port == b.port;
}
