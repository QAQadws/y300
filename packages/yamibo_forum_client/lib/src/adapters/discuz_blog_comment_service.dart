import 'dart:convert';

import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_comments.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../session/forum_session_store.dart';
import 'discuz_blog_command_response.dart';
import 'discuz_blog_mutation_session.dart';
import 'discuz_blog_comment_form.dart';
import 'discuz_profile_html_parsers.dart';

/// Comment forms and commands, sharing the Host's transport and session.
final class DiscuzBlogCommentService implements UserBlogCommentService {
  /// Creates the adapter at the composition root.
  const DiscuzBlogCommentService({
    required this.config,
    required this.network,
    required this.requestProfiles,
    required this.sessions,
  });

  /// Managed site configuration.
  final ForumClientConfig config;

  /// Shared Cookie/WAF-aware transport.
  final ForumClientNetwork network;

  /// Existing request identity resolver.
  final ForumRequestProfileResolver requestProfiles;

  /// Shared session projection; a missing identity cannot authorize a write.
  final ForumSessionStore? sessions;

  @override
  Future<
    DataReadResult<
      UserBlogCommentPreparation,
      DataCapabilitySet<UserBlogCommentAction>
    >
  >
  prepare(
    UserBlogCommentTarget target, {
    ForumRequestCancellation? cancellation,
  }) async {
    if (!_validTarget(target)) {
      return _readFailure('blog_comment_target_invalid');
    }
    if (cancellation?.isCancelled ?? false) {
      return _readFailure(
        'blog_comment_cancelled',
        DataReadFailureKind.cancelled,
      );
    }
    if (!_currentActor(target.actorUserId)) {
      return _readFailure(
        'blog_comment_account_changed',
        DataReadFailureKind.unauthorized,
      );
    }
    final articleUri = _articleUri(target, singleComment: true);
    final article = await _get(articleUri, target, cancellation);
    if (article.failureOrNull case final failure?) return failure.retype();
    try {
      final data = UserBlogDetailHtmlParser(siteOrigin: config.siteOrigin)
          .parse(
            html: article.dataOrNull!,
            query: UserBlogDetailQuery(
              ownerUserId: target.ownerUserId,
              blogId: target.blogId,
              commentId: target.commentId,
            ),
          );
      if (target.action == UserBlogCommentAction.add) {
        if (data.commentsOpen != true) {
          return _readFailure(
            'blog_comment_closed',
            DataReadFailureKind.business,
          );
        }
      } else if (!data.comments.any(
        (comment) =>
            comment.commentId == target.commentId &&
            comment.actions.contains(target.action),
      )) {
        return _readFailure(
          'blog_comment_action_denied',
          DataReadFailureKind.business,
        );
      }
      var formSource = article.dataOrNull!;
      if (target.action != UserBlogCommentAction.add) {
        final form = await _get(
          config.siteOrigin.replace(
            path: '/home.php',
            queryParameters: {
              'mod': 'spacecp',
              'ac': 'comment',
              'op': target.action.name,
              'cid': target.commentId!,
              'mobile': '2',
            },
          ),
          target,
          cancellation,
        );
        if (form.failureOrNull case final failure?) return failure.retype();
        formSource = form.dataOrNull!;
      }
      final parsed = DiscuzBlogCommentForm.parse(
        formSource,
        siteOrigin: config.siteOrigin,
        target: target,
      );
      final token = _CommentToken(owner: this, target: target, form: parsed);
      return DataReadSuccess(
        data: UserBlogCommentPreparation(
          target: target,
          token: token,
          initialMessage: parsed.message,
        ),
        capabilities: DataCapabilitySet.supported([target.action]),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _readFailure(
        'blog_comment_form_unsupported',
        DataReadFailureKind.unsupported,
      );
    }
  }

  @override
  Future<DataCommandResult<UserBlogCommentReceipt>> execute(
    UserBlogCommentSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _CommentToken ||
        !identical(token.owner, this) ||
        token.target != preparation.target ||
        token.used) {
      return _notSent('blog_comment_preparation_invalid');
    }
    final target = token.target;
    if (submission.actorUserId != target.actorUserId ||
        !_currentActor(target.actorUserId)) {
      return _notSent(
        'blog_comment_account_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent(
        'blog_comment_cancelled',
        DataCommandFailureKind.cancelled,
      );
    }
    final message = submission.message;
    if (target.action == UserBlogCommentAction.delete
        ? message.isNotEmpty
        : utf8.encode(message.trim()).length < 2) {
      return _notSent('blog_comment_message_invalid');
    }
    // Consume before the first await: concurrent taps and retries after an
    // uncertain result cannot reuse this form to create a second comment.
    token.used = true;
    final referer = _articleUri(target);
    final result = await _boundary.submit(
      token.form.actionUri.replace(
        queryParameters: {
          ...token.form.actionUri.queryParameters,
          'mobile': '2',
        },
      ),
      actor: target.actorUserId,
      referer: referer,
      operation: 'blog.comment.submit',
      handleKey: 'y300_blog_comment',
      fields: {
        ...token.form.fields,
        if (target.action != UserBlogCommentAction.delete) 'message': message,
      },
      cancellation: submission.cancellation,
    );
    if (result is! DataCommandApplied<DiscuzBlogCommandResponse>) {
      return retypeBlogCommandFailure(result);
    }
    final outcome = result.receipt;
    final cid = _confirmedCommentId(outcome, target);
    if (cid == null) return _unknown('blog_comment_receipt_identity_mismatch');
    return DataCommandApplied(
      UserBlogCommentReceipt(target: target, commentId: cid),
    );
  }

  Future<DataReadResult<String, Object?>> _get(
    Uri uri,
    UserBlogCommentTarget target,
    ForumRequestCancellation? cancellation,
  ) => _boundary.read(
    uri,
    actor: target.actorUserId,
    referer: _articleUri(target),
    operation: 'blog.comment.prepare',
    cancellation: cancellation,
  );

  DiscuzBlogMutationSession get _boundary => DiscuzBlogMutationSession(
    config: config,
    network: network,
    profiles: requestProfiles,
    sessions: sessions,
  );

  String? _confirmedCommentId(
    DiscuzBlogCommandResponse outcome,
    UserBlogCommentTarget target,
  ) {
    try {
      final cid = outcome.commentId;
      final redirect = Uri.tryParse(outcome.redirect ?? '');
      final location = redirect == null
          ? null
          : config.siteOrigin.resolveUri(redirect);
      if (cid == null ||
          !_positive(cid) ||
          location == null ||
          !_sameSite(location) ||
          location.path != '/home.php' ||
          location.queryParameters['mod'] != 'space' ||
          location.queryParameters['do'] != 'blog' ||
          location.queryParameters['uid'] != target.ownerUserId ||
          location.queryParameters['id'] != target.blogId ||
          ((target.action == UserBlogCommentAction.edit ||
                  target.action == UserBlogCommentAction.delete) &&
              cid != target.commentId)) {
        return null;
      }
      return cid;
    } on FormatException {
      return null;
    }
  }

  bool _currentActor(String id) => _boundary.currentActor(id);
  bool _sameSite(Uri uri) => _boundary.sameSite(uri);

  Uri _articleUri(UserBlogCommentTarget target, {bool singleComment = false}) =>
      config.siteOrigin.replace(
        path: '/home.php',
        queryParameters: {
          'mod': 'space',
          'uid': target.ownerUserId,
          'do': 'blog',
          'id': target.blogId,
          'mobile': '2',
          if (singleComment && target.commentId != null)
            'cid': target.commentId!,
        },
      );
}

final class _CommentToken implements UserBlogCommentPreparationToken {
  _CommentToken({
    required this.owner,
    required this.target,
    required this.form,
  });
  final DiscuzBlogCommentService owner;
  final UserBlogCommentTarget target;
  final DiscuzBlogCommentForm form;
  bool used = false;
}

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);
bool _validTarget(UserBlogCommentTarget target) =>
    _positive(target.actorUserId) &&
    _positive(target.ownerUserId) &&
    _positive(target.blogId) &&
    (target.action == UserBlogCommentAction.add
        ? target.commentId == null
        : target.commentId != null && _positive(target.commentId!));
DataReadFailure<T, C> _readFailure<T, C>(
  String code, [
  DataReadFailureKind kind = DataReadFailureKind.parse,
]) => DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
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
DataCommandNotSent<T> _notSent<T>(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.validation,
]) => DataCommandNotSent(
  _failure(code, kind, DataCommandRetryPolicy.explicitOnly),
);
DataCommandOutcomeUnknown<T> _unknown<T>(
  String code, [
  DataCommandFailureKind kind = DataCommandFailureKind.parse,
]) => DataCommandOutcomeUnknown(
  _failure(code, kind, DataCommandRetryPolicy.never),
);
