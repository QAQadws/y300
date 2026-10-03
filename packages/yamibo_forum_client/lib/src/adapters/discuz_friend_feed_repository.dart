import 'package:html/parser.dart' as html;

import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/friend_feed.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../session/forum_session_store.dart';
import 'discuz_friend_feed_parser.dart';
import 'discuz_profile_html_parsers.dart';

/// Account-bound touch friend-page reads using only the shared Host transport.
final class DiscuzFriendFeedRepository implements ForumFriendFeedRepository {
  /// Creates a network-only source for the current account's four member lists.
  DiscuzFriendFeedRepository({
    required this.config,
    required this.network,
    required this.profiles,
    this.sessions,
  }) : _parser = DiscuzFriendFeedParser(siteOrigin: config.siteOrigin);

  /// Managed site and request configuration.
  final ForumClientConfig config;

  /// Shared Host transport.
  final ForumClientNetwork network;

  /// Host-supplied request profiles.
  final ForumRequestProfileResolver profiles;

  /// Shared authenticated account projection.
  final ForumSessionStore? sessions;
  final DiscuzFriendFeedParser _parser;

  @override
  ForumFriendFeedSourceCapabilities get capabilities =>
      ForumFriendFeedSourceCapabilities(
        values: DataCapabilitySet.from(
          supported: ForumFriendFeedCapability.values.where(
            (value) => value != ForumFriendFeedCapability.visitedAtText,
          ),
          unsupported: const [ForumFriendFeedCapability.visitedAtText],
        ),
      );

  @override
  Future<DataReadResult<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>>
  load(
    ForumFriendFeedQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (!discuzFriendPositiveId(query.accountUserId) || query.page < 1) {
      return _failure(
        'friend_feed_query_invalid',
        DataReadFailureKind.business,
      );
    }
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    if (!_currentActor(query.accountUserId)) {
      return _failure(
        'friend_feed_account_changed',
        DataReadFailureKind.unauthorized,
      );
    }
    final parameters = <String, String>{
      'mod': 'space',
      'do': 'friend',
      'uid': query.accountUserId,
      'page': '${query.page}',
      'mobile': '2',
      ...switch (query.scope) {
        ForumFriendFeedScope.friends => <String, String>{},
        ForumFriendFeedScope.online => {'view': 'online', 'type': 'member'},
        ForumFriendFeedScope.visitors => {'view': 'visitor'},
        ForumFriendFeedScope.footprints => {'view': 'trace'},
      },
    };
    final uri = config.siteOrigin
        .resolve('home.php')
        .replace(queryParameters: parameters);
    final ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: uri,
          context: ForumRequestContext(
            operation: 'friends.feed.read',
            module: 'profile',
            pageKind: 'profile.friends.${query.scope.name}',
          ),
          headers: profiles.resolve(ForumRequestProfileKind.mobileHtml).headers,
          followRedirects: false,
          cancellation: query.cancellation,
        ),
      );
    } on Object {
      return _failure(
        'friend_feed_transport_failed',
        DataReadFailureKind.network,
      );
    }
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    if (!_currentActor(query.accountUserId)) {
      return _failure(
        'friend_feed_account_changed',
        DataReadFailureKind.unauthorized,
      );
    }
    if (result case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(
        'friend_feed_transport_failed',
        toReadFailureKind(failure.kind),
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _failure(
        'friend_feed_login_required',
        DataReadFailureKind.unauthorized,
      );
    }
    if (response.statusCode != 200 || response.body is! String) {
      return _failure(
        'friend_feed_response_invalid',
        DataReadFailureKind.server,
      );
    }
    final source = response.body as String;
    if (DiscuzProfileAuthPageDetector.isLoginPage(source)) {
      return _failure(
        'friend_feed_login_required',
        DataReadFailureKind.unauthorized,
      );
    }
    final document = html.parse(source);
    if (document.querySelector('#messagetext, .jump_c, .alert_error') != null) {
      return _failure('friend_feed_unavailable', DataReadFailureKind.business);
    }
    try {
      if (!_parser.isExpectedResponseUri(response.uri, query)) {
        return _failure(
          'friend_feed_context_invalid',
          DataReadFailureKind.parse,
        );
      }
      final page = _parser.parse(source, query);
      var values = capabilities.values;
      final optional = {
        ForumFriendFeedCapability.avatar: page.items.any(
          (item) => item.avatarUrl != null,
        ),
        ForumFriendFeedCapability.note: page.items.any(
          (item) => item.note != null,
        ),
        ForumFriendFeedCapability.onlineStatus: page.items.any(
          (item) => item.isOnline != null,
        ),
        ForumFriendFeedCapability.removal: page.items.any(
          (item) => item.canRemove,
        ),
      };
      for (final entry in optional.entries) {
        if (!entry.value) {
          values = values.withSupport(entry.key, DataCapabilitySupport.unknown);
        }
      }
      return DataReadSuccess(
        data: page,
        capabilities: ForumFriendFeedReadCapabilities(values: values),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _failure('friend_feed_parse_failed', DataReadFailureKind.parse);
    }
  }

  bool _currentActor(String actor) {
    final store = sessions;
    if (store == null) return true;
    final current = store.readCurrent();
    return current != null && current.isLoggedIn && current.userId == actor;
  }
}

DataReadFailure<ForumFriendFeedPage, ForumFriendFeedReadCapabilities> _failure(
  String code,
  DataReadFailureKind kind,
) => DataReadFailure(kind: kind, code: code, diagnosticMessage: code);

DataReadFailure<ForumFriendFeedPage, ForumFriendFeedReadCapabilities>
_cancelled() =>
    _failure('friend_feed_cancelled', DataReadFailureKind.cancelled);
