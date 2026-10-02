import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/forum_resource.dart';
import '../contracts/friend_directory.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_friend_literal_parser.dart';

/// Desktop friend-selector source on the Host's authenticated transport.
final class DiscuzFriendDirectoryRepository
    implements ForumFriendDirectoryRepository {
  /// Creates an uncached source for the current account's friends.
  const DiscuzFriendDirectoryRepository({
    required this.config,
    required this.network,
    required this.profiles,
  });

  /// Managed forum origin.
  final ForumClientConfig config;

  /// Shared transport, including the Host's Cookie and cancellation handling.
  final ForumClientNetwork network;

  /// Configured desktop browser identity.
  final ForumRequestProfileResolver profiles;

  @override
  ForumFriendDirectorySourceCapabilities get capabilities =>
      ForumFriendDirectorySourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumFriendDirectoryCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ForumFriendDirectoryPage,
      ForumFriendDirectoryReadCapabilities
    >
  >
  load(
    ForumFriendDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (query.page < 1 ||
        query.username.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query.username)) {
      return _failure('friend_query_invalid', DataReadFailureKind.business);
    }
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    final uri = config.siteOrigin
        .resolve('home.php')
        .replace(
          queryParameters: {
            'mod': 'spacecp',
            'ac': 'friend',
            'op': 'getinviteuser',
            'inajax': '1',
            'page': '${query.page}',
            'gid': '-1',
            if (query.username.isNotEmpty) 'username': query.username,
          },
        );
    final ForumTransportResult<ForumResponse<Object?>> result;
    try {
      result = await network.send(
        ForumRequest(
          method: ForumRequestMethod.get,
          uri: uri,
          context: const ForumRequestContext(
            operation: 'friends.read',
            pageKind: 'profile.friends',
          ),
          headers: profiles
              .resolve(
                ForumRequestProfileKind.desktopHtml,
                referer: config.siteOrigin.resolve(
                  'home.php?mod=spacecp&ac=pm',
                ),
              )
              .headers,
          followRedirects: false,
          cancellation: query.cancellation,
        ),
      );
    } on Object {
      return _failure('friend_transport_failed', DataReadFailureKind.network);
    }
    if (query.cancellation?.isCancelled ?? false) return _cancelled();
    if (result case ForumTransportError(:final failure)) {
      return _failure(
        'friend_transport_failed',
        toReadFailureKind(failure.kind),
      );
    }
    final response =
        (result as ForumTransportSuccess<ForumResponse<Object?>>).response;
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _failure(
        'friend_session_unavailable',
        DataReadFailureKind.unauthorized,
      );
    }
    if (response.statusCode != 200 ||
        response.uri != uri ||
        response.body is! String ||
        (response.body! as String).length > 131072) {
      return _failure(
        'friend_response_unrecognized',
        DataReadFailureKind.parse,
      );
    }
    try {
      final body = response.body as String;
      // Discuz wraps the literal in one XML CDATA root. Accepting arbitrary
      // script or trailing markup would turn a data endpoint into code parsing.
      final envelope = RegExp(
        r'^\s*(?:<\?xml\s[^?]*\?>\s*)?<root>\s*<!\[CDATA\[([\s\S]*)\]\]>\s*</root>\s*$',
      ).firstMatch(body);
      if (envelope == null) throw const FormatException('friend_envelope');
      final literal = envelope.group(1)!;
      if (literal.contains('<![CDATA[') || literal.contains(']]>')) {
        throw const FormatException('friend_envelope');
      }
      final data = DiscuzFriendLiteralParser().parse(literal);
      if (data.length != 3 || data['userdata'] is! Map<String, Object?>) {
        throw const FormatException('friend_shape');
      }
      final count = _count(data['maxfriendnum']);
      final single = _count(data['singlenum']);
      final rows = data['userdata']! as Map<String, Object?>;
      if (count == null ||
          single == null ||
          single != rows.length ||
          rows.length > 20 ||
          count < rows.length) {
        throw const FormatException('friend_count');
      }
      final resolver = ForumResourceReferenceResolver(
        siteOrigin: config.siteOrigin,
      );
      final items = <ForumFriendDirectoryItem>[];
      for (final entry in rows.entries) {
        final row = entry.value;
        if (row is! Map<String, Object?> ||
            row.length != 3 ||
            !RegExp(r'^[1-9]\d*$').hasMatch(entry.key) ||
            row['uid'] is! int ||
            '${row['uid']}' != entry.key ||
            row['username'] is! String ||
            row['avatar'] is! String) {
          throw const FormatException('friend_identity');
        }
        final username = row['username']! as String;
        if (username.trim().isEmpty ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(username)) {
          throw const FormatException('friend_username');
        }
        items.add(
          ForumFriendDirectoryItem(
            userId: entry.key,
            username: username,
            avatarUrl: resolver
                .resolve(row['avatar']! as String)
                ?.uri
                .toString(),
          ),
        );
      }
      return DataReadSuccess(
        data: ForumFriendDirectoryPage(
          items: List.unmodifiable(items),
          page: query.page,
          perPage: 20,
          count: count,
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return _failure(
        'friend_response_unrecognized',
        DataReadFailureKind.parse,
      );
    }
  }
}

int? _count(Object? value) =>
    value is String && RegExp(r'^\d{1,10}$').hasMatch(value)
    ? int.tryParse(value)
    : null;

DataReadFailure<ForumFriendDirectoryPage, ForumFriendDirectoryReadCapabilities>
_failure(String code, DataReadFailureKind kind) =>
    DataReadFailure(kind: kind, code: code, diagnosticMessage: code);

DataReadFailure<ForumFriendDirectoryPage, ForumFriendDirectoryReadCapabilities>
_cancelled() => _failure('request_cancelled', DataReadFailureKind.cancelled);
