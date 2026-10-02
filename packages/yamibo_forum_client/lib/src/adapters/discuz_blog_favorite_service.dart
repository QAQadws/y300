import '../client/forum_client_config.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_favorites.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../session/forum_session_store.dart';
import 'discuz_blog_favorite_form.dart';
import 'discuz_blog_mutation_session.dart';
import 'discuz_profile_html_parsers.dart';

/// Personal journal bookmarks over the existing account-bound Host transport.
final class DiscuzBlogFavoriteService implements UserBlogFavoriteService {
  /// Reuses the forum session, request profiles, and shared transport.
  DiscuzBlogFavoriteService({
    required ForumClientConfig config,
    required ForumClientNetwork network,
    required ForumRequestProfileResolver profiles,
    required ForumSessionStore? sessions,
  }) : _boundary = DiscuzBlogMutationSession(
         config: config,
         network: network,
         profiles: profiles,
         sessions: sessions,
       );

  final DiscuzBlogMutationSession _boundary;
  Uri get _origin => _boundary.config.siteOrigin;

  @override
  Future<DataReadResult<UserBlogFavoritePreparation, Object?>> prepare(
    UserBlogFavoriteTarget target, {
    ForumRequestCancellation? cancellation,
  }) async {
    if (![
      target.actorUserId,
      target.ownerUserId,
      target.blogId,
    ].every(_positive)) {
      return _readFailure('blog_favorite_target_invalid');
    }
    final source = await _boundary.read(
      _articleUri(target),
      actor: target.actorUserId,
      referer: _articleUri(target),
      operation: 'blog.favorite.article',
      cancellation: cancellation,
    );
    if (source.failureOrNull case final failure?) return failure.retype();
    try {
      final article = UserBlogDetailHtmlParser(siteOrigin: _origin).parse(
        html: source.dataOrNull!,
        query: UserBlogDetailQuery(
          ownerUserId: target.ownerUserId,
          blogId: target.blogId,
        ),
      );
      if (!article.socialActions.contains(UserBlogSocialAction.favorite)) {
        return _readFailure(
          'blog_favorite_denied',
          DataReadFailureKind.business,
        );
      }
      final result = await _boundary.read(
        _favoriteUri(target),
        actor: target.actorUserId,
        referer: _articleUri(target),
        operation: 'blog.favorite.form',
        cancellation: cancellation,
        allowBusinessNotice: true,
        requireExactUri: true,
      );
      if (result.failureOrNull case final failure?) return failure.retype();
      final content = result.dataOrNull!;
      if (DiscuzBlogFavoriteForm.isNotice(content)) {
        // A duplicate message alone carries neither an account-owned bookmark
        // ID nor a safe write receipt. Prove it using the targeted read-only GET.
        final existing = await _boundary.read(
          _favoriteUri(target, existing: true),
          actor: target.actorUserId,
          referer: _articleUri(target),
          operation: 'blog.favorite.existing',
          cancellation: cancellation,
          requireExactUri: true,
        );
        if (existing.failureOrNull case final failure?) return failure.retype();
        final id = DiscuzBlogFavoriteForm.existingId(
          existing.dataOrNull!,
          _origin,
        );
        return _ready(
          UserBlogFavoritePreparation.alreadySaved(
            target: target,
            favoriteId: id,
          ),
        );
      }
      final form = DiscuzBlogFavoriteForm.parse(content, _origin, target);
      return _ready(
        UserBlogFavoritePreparation.ready(
          target: target,
          token: _FavoriteToken(this, target, form),
        ),
      );
    } on FormatException {
      return _readFailure(
        'blog_favorite_form_unsupported',
        DataReadFailureKind.unsupported,
      );
    }
  }

  @override
  Future<DataCommandResult<UserBlogFavoriteReceipt>> add(
    UserBlogFavoritePreparation preparation, {
    required String actorUserId,
    required String description,
    ForumRequestCancellation? cancellation,
  }) async {
    final token = preparation.token;
    if (token is! _FavoriteToken ||
        token.owner != this ||
        token.used ||
        token.target != preparation.target ||
        preparation.existingFavoriteId != null) {
      return _notSent('blog_favorite_ticket_invalid');
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
      token.form.actionUri,
      actor: actorUserId,
      referer: _articleUri(token.target),
      operation: 'blog.favorite.submit',
      handleKey: 'y300_blog_favorite',
      fields: {...token.form.fields, 'description': description},
      cancellation: cancellation,
    );
    if (result case DataCommandApplied(:final receipt)) {
      if (receipt.itemId == token.target.blogId &&
          _positive(receipt.favoriteId ?? '') &&
          _receiptUri(receipt.redirect, token.target)) {
        return DataCommandApplied(
          UserBlogFavoriteReceipt(
            target: token.target,
            favoriteId: receipt.favoriteId!,
          ),
        );
      }
      return const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.parse,
          retryPolicy: DataCommandRetryPolicy.never,
          code: 'blog_favorite_receipt_unproved',
          diagnosticMessage: 'blog_favorite_receipt_unproved',
        ),
      );
    }
    return retypeBlogCommandFailure(result);
  }

  Uri _articleUri(UserBlogFavoriteTarget target) => _origin.replace(
    path: '/home.php',
    queryParameters: {
      'mod': 'space',
      'uid': target.ownerUserId,
      'do': 'blog',
      'id': target.blogId,
      'mobile': '2',
    },
  );
  Uri _favoriteUri(UserBlogFavoriteTarget target, {bool existing = false}) =>
      _origin.replace(
        path: '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'favorite',
          'type': 'blog',
          'id': target.blogId,
          if (existing) 'op': 'delete' else 'spaceuid': target.ownerUserId,
          'mobile': '2',
        },
      );

  bool _receiptUri(String? raw, UserBlogFavoriteTarget target) {
    if (raw == null || raw.isEmpty) return false;
    try {
      final uri = _origin.resolve(raw.replaceAll('&amp;', '&'));
      final query = uri.queryParameters;
      return _boundary.sameSite(uri) &&
          uri.path == '/home.php' &&
          !uri.hasFragment &&
          uri.queryParametersAll.values.every((values) => values.length == 1) &&
          query.keys.every({'mod', 'uid', 'do', 'id', 'mobile'}.contains) &&
          query['mod'] == 'space' &&
          query['uid'] == target.ownerUserId &&
          query['do'] == 'blog' &&
          query['id'] == target.blogId &&
          {null, '2'}.contains(query['mobile']);
    } on FormatException {
      return false;
    }
  }
}

final class _FavoriteToken implements UserBlogFavoriteToken {
  _FavoriteToken(this.owner, this.target, this.form);
  final DiscuzBlogFavoriteService owner;
  final UserBlogFavoriteTarget target;
  final DiscuzBlogFavoriteForm form;
  bool used = false;
}

bool _positive(String id) => RegExp(r'^[1-9]\d*$').hasMatch(id);
DataReadSuccess<UserBlogFavoritePreparation, Object?> _ready(
  UserBlogFavoritePreparation preparation,
) => DataReadSuccess(
  data: preparation,
  capabilities: null,
  metadata: const DataReadMetadata.network(),
);
DataReadFailure<T, C> _readFailure<T, C>(
  String code, [
  DataReadFailureKind kind = DataReadFailureKind.parse,
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
