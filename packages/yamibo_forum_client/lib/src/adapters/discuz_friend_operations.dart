import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_friend_operations.dart';
import '../contracts/profile_and_blog.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'discuz_blog_command_response.dart';
import 'discuz_friend_form.dart';
import 'discuz_profile_action_links.dart';
import 'discuz_profile_html_parsers.dart';

/// Complete friendship forms and one-use commands on the shared Host session.
final class DiscuzFriendOperations implements ForumFriendOperations {
  /// Creates a friendship adapter without owning a second transport/session.
  DiscuzFriendOperations({
    required this.config,
    required this.network,
    required this.profiles,
    required this.sessions,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Managed forum configuration.
  final ForumClientConfig config;

  /// Shared Host transport.
  final ForumClientNetwork network;

  /// Shared request profiles.
  final ForumRequestProfileResolver profiles;

  /// Shared, verified session projection.
  final ForumSessionStore? sessions;
  final DateTime Function() _now;
  int _ticketSequence = 0;

  bool _currentActor(String id) {
    final session = sessions?.readCurrent();
    return session != null && session.isLoggedIn && session.userId == id;
  }

  @override
  Future<DataReadResult<ForumFriendPreparation, ForumFriendReadCapabilities>>
  prepare(ForumFriendQuery query) async {
    final actor = query.actorUserId;
    final target = query.targetUserId;
    final kind = DiscuzProfileActionLinks(
      config.siteOrigin,
    ).classify(query.actionLink.uri, userId: target, viewerUserId: actor);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(actor) ||
        !RegExp(r'^[1-9]\d*$').hasMatch(target) ||
        actor == target ||
        kind != query.actionLink.kind ||
        !{
          ForumUserProfileActionKind.addFriend,
          ForumUserProfileActionKind.removeFriend,
        }.contains(kind)) {
      return _readFailure(
        'friend_target_invalid',
        DataReadFailureKind.business,
      );
    }
    if (!_currentActor(actor)) {
      return _readFailure(
        'friend_actor_changed',
        DataReadFailureKind.unauthorized,
      );
    }
    if (query.cancellation?.isCancelled ?? false) {
      return _readFailure('friend_cancelled', DataReadFailureKind.cancelled);
    }
    final uri = query.actionLink.uri.replace(
      queryParameters: {...query.actionLink.uri.queryParameters, 'mobile': '2'},
    );
    ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: uri,
          context: const ForumRequestContext(
            operation: 'profile.friend.prepare',
            module: 'profile',
            pageKind: 'profile.friend.form',
            silent: true,
          ),
          headers: profiles
              .resolve(
                ForumRequestProfileKind.mobileHtml,
                referer: _referer(target),
              )
              .headers,
          followRedirects: false,
          cancellation: query.cancellation,
        ),
      );
    } catch (_) {
      return _readFailure(
        'friend_transport_failed',
        DataReadFailureKind.network,
      );
    }
    if (query.cancellation?.isCancelled ?? false) {
      return _readFailure('friend_cancelled', DataReadFailureKind.cancelled);
    }
    if (!_currentActor(actor)) {
      return _readFailure(
        'friend_actor_changed',
        DataReadFailureKind.unauthorized,
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _readFailure(
        'friend_transport_failed',
        toReadFailureKind(failure.kind),
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        response.uri != uri ||
        response.body is! String) {
      return _readFailure('friend_response_invalid', DataReadFailureKind.parse);
    }
    final source = response.body as String;
    if (DiscuzProfileAuthPageDetector.isLoginPage(source)) {
      return _readFailure(
        'friend_unauthorized',
        DataReadFailureKind.unauthorized,
      );
    }
    try {
      final form = DiscuzFriendForm.parse(
        source,
        origin: config.siteOrigin,
        actor: actor,
        target: target,
        removing: kind == ForumUserProfileActionKind.removeFriend,
      );
      final token = _FriendToken(
        this,
        actor,
        target,
        form,
        _now(),
        'y300friend_${actor}_${target}_${++_ticketSequence}',
      );
      return DataReadSuccess(
        data: ForumFriendPreparation(
          actorUserId: actor,
          targetUserId: target,
          action: form.action,
          token: token,
          groups: form.groups,
          selectedGroupId: form.selectedGroupId,
        ),
        capabilities: ForumFriendReadCapabilities(action: form.action),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _readFailure(
        'friend_form_unsupported',
        DataReadFailureKind.unsupported,
      );
    }
  }

  @override
  Future<DataCommandResult<ForumFriendReceipt>> submit(
    ForumFriendSubmission submission,
  ) async {
    final preparation = submission.preparation;
    final token = preparation.token;
    if (token is! _FriendToken ||
        token.owner != this ||
        token.used ||
        preparation.actorUserId != token.actor ||
        preparation.targetUserId != token.target ||
        preparation.action != token.form.action ||
        _now().difference(token.createdAt).isNegative ||
        _now().difference(token.createdAt) > const Duration(minutes: 5)) {
      return _notSent('friend_ticket_invalid');
    }
    if (submission.actorUserId != token.actor || !_currentActor(token.actor)) {
      return _notSent(
        'friend_actor_changed',
        DataCommandFailureKind.unauthenticated,
      );
    }
    if (submission.cancellation?.isCancelled ?? false) {
      return _notSent('friend_cancelled', DataCommandFailureKind.cancelled);
    }
    final form = token.form;
    final groupId = submission.groupId ?? form.selectedGroupId;
    if ((form.action != ForumFriendAction.remove &&
            !form.groups.any((group) => group.id == groupId)) ||
        (form.action == ForumFriendAction.remove &&
            submission.groupId != null) ||
        (form.action != ForumFriendAction.request &&
            submission.note.isNotEmpty) ||
        submission.note.runes.length > 30) {
      return _notSent('friend_submission_invalid');
    }
    // Consume before the first side effect; an uncertain response never reuses it.
    token.used = true;
    final handleKey = token.handleKey;
    final uri = form.uri.replace(
      queryParameters: {
        ...form.uri.queryParameters,
        'mobile': '2',
        'inajax': '1',
        'handlekey': handleKey,
      },
    );
    ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.post,
          uri: uri,
          context: const ForumRequestContext(
            operation: 'profile.friend.submit',
            module: 'profile',
            pageKind: 'profile.friend.form',
            silent: true,
          ),
          headers: profiles
              .resolve(
                ForumRequestProfileKind.mobileHtml,
                referer: _referer(token.target),
              )
              .headers,
          body: {
            ...form.hidden,
            'referer': _referer(token.target).toString(),
            'handlekey': handleKey,
            'gid': ?groupId,
            if (form.action == ForumFriendAction.request)
              'note': submission.note,
          },
          followRedirects: false,
          allowWafReplay: false,
          cancellation: submission.cancellation,
        ),
      );
    } catch (_) {
      return _unknown(
        'friend_transport_failed',
        DataCommandFailureKind.network,
      );
    }
    if ((submission.cancellation?.isCancelled ?? false) ||
        !_currentActor(token.actor)) {
      return _unknown(
        'friend_operation_interrupted',
        DataCommandFailureKind.cancelled,
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _unknown(
        'friend_transport_failed',
        failure.kind == ForumTransportFailureKind.timeout
            ? DataCommandFailureKind.timeout
            : DataCommandFailureKind.network,
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode != 200 ||
        response.uri != uri ||
        response.body is! String) {
      return _unknown('friend_response_invalid');
    }
    final outcome = DiscuzBlogCommandResponse.parse(
      response.body as String,
      handleKey,
    );
    if (outcome == null) return _unknown('friend_response_unproved');
    if (!outcome.applied) {
      return DataCommandRejected(
        _failure(
          'friend_operation_rejected',
          DataCommandFailureKind.validation,
          DataCommandRetryPolicy.afterInputChange,
        ),
      );
    }
    final redirect = outcome.redirect;
    final expectedRedirect = form.action == ForumFriendAction.remove
        ? config.siteOrigin.resolve('home.php?mod=spacecp&ac=friend&op=request')
        : _referer(token.target);
    Uri? redirectUri;
    try {
      redirectUri = redirect == null
          ? null
          : config.siteOrigin.resolve(redirect);
    } on FormatException {
      return _unknown('friend_receipt_unproved');
    }
    if (redirectUri != expectedRedirect ||
        (outcome.userId != null && outcome.userId != token.target) ||
        (form.action != ForumFriendAction.request &&
            outcome.userId != token.target)) {
      return _unknown('friend_receipt_unproved');
    }
    return DataCommandApplied(
      ForumFriendReceipt(
        actorUserId: token.actor,
        targetUserId: token.target,
        action: form.action,
      ),
    );
  }

  Uri _referer(String target) => config.siteOrigin.replace(
    path: '/home.php',
    queryParameters: {
      'mod': 'space',
      'uid': target,
      'do': 'profile',
      'mobile': '2',
    },
  );
}

final class _FriendToken implements ForumFriendOperationToken {
  _FriendToken(
    this.owner,
    this.actor,
    this.target,
    this.form,
    this.createdAt,
    this.handleKey,
  );
  final DiscuzFriendOperations owner;
  final String actor;
  final String target;
  final DiscuzFriendForm form;
  final DateTime createdAt;
  final String handleKey;
  bool used = false;
}

DataReadFailure<T, C> _readFailure<T, C>(
  String code,
  DataReadFailureKind kind,
) => DataReadFailure(kind: kind, code: code, diagnosticMessage: code);
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
