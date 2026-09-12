import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_operations.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../session/forum_session_store.dart';
import 'discuz_blog_command_response.dart';
import 'discuz_blog_editor_form.dart';
import 'discuz_blog_mutation_session.dart';
import 'discuz_profile_html_parsers.dart';

/// Complete journal forms and verified publishing/management commands.
final class DiscuzBlogOperations implements UserBlogOperations {
  /// Creates the adapter with the existing Host session and transport.
  DiscuzBlogOperations({
    required this.config,
    required ForumClientNetwork network,
    required ForumRequestProfileResolver profiles,
    required ForumSessionStore? sessions,
  }) : _boundary = DiscuzBlogMutationSession(
         config: config,
         network: network,
         profiles: profiles,
         sessions: sessions,
       );

  /// Managed site configuration.
  final ForumClientConfig config;
  final DiscuzBlogMutationSession _boundary;

  @override
  Future<
    DataReadResult<UserBlogEditorPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareEditor(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) async {
    if (!_validTarget(target) ||
        !{UserBlogAction.create, UserBlogAction.edit}.contains(target.action)) {
      return _readFailure('blog_editor_target_invalid');
    }
    final source = await _boundary.read(
      _formUri(target, desktop: true),
      actor: target.actorUserId,
      referer: _referer(target),
      operation: 'blog.editor.prepare',
      profile: ForumRequestProfileKind.desktopHtml,
      cancellation: cancellation,
    );
    if (source.failureOrNull case final failure?) return failure.retype();
    try {
      final form = DiscuzBlogEditorForm.parse(
        source.dataOrNull!,
        siteOrigin: config.siteOrigin,
        target: target,
      );
      final token = _EditorToken(owner: this, target: target, form: form);
      return DataReadSuccess(
        data: form.preparation(target, token),
        capabilities: DataCapabilitySet.supported([target.action]),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _readFailure(
        'blog_editor_form_unsupported',
        DataReadFailureKind.unsupported,
      );
    }
  }

  @override
  Future<DataCommandResult<UserBlogReceipt>> save(
    UserBlogEditorSubmission submission,
  ) async {
    final token = submission.preparation.token;
    if (token is! _EditorToken ||
        token.owner != this ||
        token.target != submission.preparation.target ||
        token.used) {
      return _notSent('blog_editor_ticket_invalid');
    }
    if (submission.actorUserId != token.target.actorUserId ||
        !_boundary.currentActor(submission.actorUserId)) {
      return _notSent(
        'blog_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent(
        'blog_operation_cancelled',
        DataCommandFailureKind.cancelled,
      );
    }
    final form = token.form;
    final newCategory = submission.newPersonalCategory?.trim();
    final siteValid = form.siteCategories.isEmpty
        ? submission.siteCategoryId == '0'
        : form.siteCategories.any(
            (value) => value.id == submission.siteCategoryId,
          );
    if (submission.subject.trim().isEmpty ||
        submission.bodyHtml.trim().isEmpty ||
        !siteValid ||
        (form.siteCategoryRequired && submission.siteCategoryId == '0') ||
        !form.personalCategories.any(
          (value) => value.id == submission.personalCategoryId,
        ) ||
        (newCategory != null &&
            (newCategory.isEmpty ||
                !form.canCreateCategory ||
                submission.personalCategoryId != '0')) ||
        (submission.publishFeed && !form.canPublishFeed)) {
      return _notSent('blog_editor_input_invalid');
    }
    token.used = true;
    final result = await _boundary.submit(
      form.actionUri.replace(
        queryParameters: {...form.actionUri.queryParameters, 'mobile': 'no'},
      ),
      actor: submission.actorUserId,
      referer: _referer(token.target),
      operation: 'blog.editor.submit',
      handleKey: 'y300_blog_editor',
      profile: ForumRequestProfileKind.desktopHtml,
      multipart: true,
      cancellation: submission.cancellation,
      fields: {
        ...form.fields,
        'subject': submission.subject,
        'message': submission.bodyHtml,
        'tag': submission.tags,
        'catid': submission.siteCategoryId,
        'classid': newCategory == null
            ? submission.personalCategoryId
            : 'new:$newCategory',
        if (form.canPublishFeed) 'makefeed': submission.publishFeed ? '1' : '0',
      },
    );
    return _receipt(result, token.target);
  }

  @override
  Future<
    DataReadResult<UserBlogActionPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareAction(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  }) async {
    if (!_validTarget(target) ||
        !{
          UserBlogAction.delete,
          UserBlogAction.pin,
          UserBlogAction.unpin,
        }.contains(target.action)) {
      return _readFailure('blog_action_target_invalid');
    }
    final source = await _boundary.read(
      _referer(target),
      actor: target.actorUserId,
      referer: _referer(target),
      operation: 'blog.action.prepare',
      cancellation: cancellation,
    );
    if (source.failureOrNull case final failure?) return failure.retype();
    try {
      final article = UserBlogDetailHtmlParser(siteOrigin: config.siteOrigin)
          .parse(
            html: source.dataOrNull!,
            query: UserBlogDetailQuery(
              ownerUserId: target.ownerUserId,
              blogId: target.blogId!,
            ),
          );
      // Discuz only advertises pinning in the author's directory, but the
      // same endpoint also provides the inverse operation for that author.
      if (target.action == UserBlogAction.delete
          ? !article.actions.contains(UserBlogAction.delete)
          : target.actorUserId != target.ownerUserId) {
        return _readFailure('blog_action_denied', DataReadFailureKind.business);
      }
      final confirmation = await _boundary.read(
        _formUri(target),
        actor: target.actorUserId,
        referer: _referer(target),
        operation: 'blog.action.form',
        cancellation: cancellation,
      );
      if (confirmation.failureOrNull case final failure?) {
        return failure.retype();
      }
      final forms = html
          .parse(confirmation.dataOrNull!)
          .querySelectorAll('form')
          .where(
            (form) => (form.attributes['action'] ?? '').contains('ac=blog'),
          )
          .toList();
      if (forms.length != 1) {
        throw const FormatException('blog_action_form_missing');
      }
      final form = forms.single;
      final uri = blogFormAction(
        form,
        siteOrigin: config.siteOrigin,
        target: target,
      );
      final flag = target.action == UserBlogAction.delete
          ? 'deletesubmit'
          : 'sticksubmit';
      final allowed = {
        'formhash',
        'referer',
        flag,
        if (flag == 'sticksubmit') 'stickflag',
      };
      final fields = <String, String>{};
      for (final control in form.querySelectorAll(
        'input[name], textarea[name], select[name], button[name]',
      )) {
        final name = control.attributes['name']!;
        if (control.localName == 'button' &&
            name == 'btnsubmit' &&
            control.attributes['type'] == 'submit' &&
            control.attributes['value'] == 'true') {
          continue;
        }
        if (!allowed.contains(name) ||
            control.localName != 'input' ||
            control.attributes['type'] != 'hidden' ||
            fields.containsKey(name) ||
            control.attributes.containsKey('disabled')) {
          throw const FormatException('blog_action_form_unsupported');
        }
        fields[name] = control.attributes['value'] ?? '';
      }
      if ((fields['formhash'] ?? '').trim().isEmpty ||
          fields[flag] != 'true' ||
          (flag == 'sticksubmit' &&
              fields['stickflag'] !=
                  (target.action == UserBlogAction.pin ? '1' : '0'))) {
        throw const FormatException('blog_action_form_invalid');
      }
      fields.remove('referer');
      final token = _ActionToken(
        owner: this,
        target: target,
        actionUri: uri,
        fields: Map.unmodifiable(fields),
      );
      return DataReadSuccess(
        data: UserBlogActionPreparation(target: target, token: token),
        capabilities: DataCapabilitySet.supported([target.action]),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _readFailure(
        'blog_action_form_unsupported',
        DataReadFailureKind.unsupported,
      );
    }
  }

  @override
  Future<DataCommandResult<UserBlogReceipt>> executeAction(
    UserBlogActionPreparation preparation, {
    required String actorUserId,
    ForumRequestCancellation? cancellation,
  }) async {
    final token = preparation.token;
    if (token is! _ActionToken ||
        token.owner != this ||
        token.target != preparation.target ||
        token.used) {
      return _notSent('blog_action_ticket_invalid');
    }
    if (actorUserId != token.target.actorUserId ||
        !_boundary.currentActor(actorUserId)) {
      return _notSent(
        'blog_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (cancellation?.isCancelled ?? false) {
      return _notSent(
        'blog_operation_cancelled',
        DataCommandFailureKind.cancelled,
      );
    }
    token.used = true;
    final result = await _boundary.submit(
      token.actionUri.replace(
        queryParameters: {...token.actionUri.queryParameters, 'mobile': '2'},
      ),
      actor: actorUserId,
      referer: _referer(token.target),
      operation: 'blog.action.submit',
      handleKey: 'y300_blog_action',
      fields: token.fields,
      cancellation: cancellation,
    );
    return _receipt(result, token.target);
  }

  DataCommandResult<UserBlogReceipt> _receipt(
    DataCommandResult<DiscuzBlogCommandResponse> result,
    UserBlogTarget target,
  ) {
    if (result is! DataCommandApplied<DiscuzBlogCommandResponse>) {
      return retypeBlogCommandFailure(result);
    }
    try {
      final destination = result.receipt.redirect;
      if (destination == null || destination.isEmpty) return _unknown();
      final uri = config.siteOrigin.resolve(destination);
      final values = uri.queryParameters;
      if (!_boundary.sameSite(uri) ||
          uri.path != '/home.php' ||
          values['mod'] != 'space' ||
          values['do'] != 'blog' ||
          values['uid'] != target.ownerUserId ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        return _unknown();
      }
      if (target.action == UserBlogAction.delete) {
        if (values['view'] != 'me' || values.containsKey('id')) {
          return _unknown();
        }
        return DataCommandApplied(
          UserBlogReceipt(target: target, blogId: target.blogId!),
        );
      }
      final id = values['id'];
      if (id == null ||
          !_positive(id) ||
          (target.blogId != null && id != target.blogId)) {
        return _unknown();
      }
      return DataCommandApplied(UserBlogReceipt(target: target, blogId: id));
    } on FormatException {
      return _unknown();
    }
  }

  Uri _referer(UserBlogTarget target) => config.siteOrigin.replace(
    path: '/home.php',
    queryParameters: {
      'mod': 'space',
      'uid': target.ownerUserId,
      'do': 'blog',
      'mobile': '2',
      if (target.blogId != null) 'id': target.blogId! else 'view': 'me',
    },
  );
  Uri _formUri(UserBlogTarget target, {bool desktop = false}) =>
      config.siteOrigin.replace(
        path: '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'blog',
          'mobile': desktop ? 'no' : '2',
          if (target.blogId != null) 'blogid': target.blogId!,
          if (target.action == UserBlogAction.edit) 'op': 'edit',
          if (target.action == UserBlogAction.delete) 'op': 'delete',
          if (target.action == UserBlogAction.pin ||
              target.action == UserBlogAction.unpin) ...{
            'op': 'stick',
            'stickflag': target.action == UserBlogAction.pin ? '1' : '0',
          },
        },
      );
}

sealed class _OperationToken implements UserBlogOperationToken {
  _OperationToken({required this.owner, required this.target});
  final DiscuzBlogOperations owner;
  final UserBlogTarget target;
  bool used = false;
}

final class _EditorToken extends _OperationToken {
  _EditorToken({
    required super.owner,
    required super.target,
    required this.form,
  });
  final DiscuzBlogEditorForm form;
}

final class _ActionToken extends _OperationToken {
  _ActionToken({
    required super.owner,
    required super.target,
    required this.actionUri,
    required this.fields,
  });
  final Uri actionUri;
  final Map<String, String> fields;
}

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);
bool _validTarget(UserBlogTarget target) =>
    _positive(target.actorUserId) &&
    _positive(target.ownerUserId) &&
    (target.action == UserBlogAction.create
        ? target.blogId == null && target.ownerUserId == target.actorUserId
        : target.blogId != null && _positive(target.blogId!));
DataReadFailure<T, C> _readFailure<T, C>(
  String code, [
  DataReadFailureKind kind = DataReadFailureKind.business,
]) => DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
DataCommandNotSent<T> _notSent<T>(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
]) => DataCommandNotSent(
  DataCommandFailure(
    kind: kind,
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    code: code,
    diagnosticMessage: code,
  ),
);
DataCommandOutcomeUnknown<T> _unknown<T>() => const DataCommandOutcomeUnknown(
  DataCommandFailure(
    kind: DataCommandFailureKind.parse,
    retryPolicy: DataCommandRetryPolicy.never,
    code: 'blog_receipt_identity_unproved',
    diagnosticMessage: 'blog_receipt_identity_unproved',
  ),
);
