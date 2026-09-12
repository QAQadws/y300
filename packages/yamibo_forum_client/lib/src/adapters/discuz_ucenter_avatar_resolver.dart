import '../contracts/forum_resource.dart';

/// Resolves the UCenter layout advertised by this response, without a profile
/// read or an assumed UCenter host. Unknown plugin layouts remain unsupported.
final class DiscuzUCenterAvatarResolver {
  /// Uses the API's current-user identity to validate its avatar template.
  DiscuzUCenterAvatarResolver({
    required Uri siteOrigin,
    required String currentUserId,
    required String currentUserAvatar,
  }) : _currentUserId = currentUserId.trim(),
       _resources = ForumResourceReferenceResolver(siteOrigin: siteOrigin),
       _avatar = ForumResourceReferenceResolver(
         siteOrigin: siteOrigin,
       ).resolve(currentUserAvatar)?.uri;

  final String _currentUserId;
  final ForumResourceReferenceResolver _resources;
  final Uri? _avatar;

  static final _uid = RegExp(r'^[1-9]\d{0,8}$');
  static final _staticPath = RegExp(
    r'^(.*\/)(\d{3})/(\d{2})/(\d{2})/(\d{2})(_real)?_avatar_(small|middle|big)\.jpg$',
  );

  /// Returns a middle-size avatar, or null when its identity is unproven.
  String? resolve(String userId) {
    try {
      return _resolve(userId);
    } on FormatException {
      // Malformed optional avatar metadata must not discard a message page.
      return null;
    }
  }

  String? _resolve(String userId) {
    final target = userId.trim();
    final avatar = _avatar;
    if (!_uid.hasMatch(target) ||
        !_uid.hasMatch(_currentUserId) ||
        avatar == null) {
      return null;
    }

    final query = avatar.queryParameters;
    if (avatar.path.endsWith('/avatar.php')) {
      if (query['uid'] != _currentUserId ||
          !{'uid', 'size', 'type', 'ts', 'random'}.containsAll(query.keys) ||
          query['type'] != null && query['type'] != 'real' ||
          avatar.queryParametersAll.values.any(
            (values) => values.length != 1,
          )) {
        return null;
      }
      return _validated(
        avatar.replace(
          queryParameters: {
            'uid': target,
            'size': 'middle',
            if (query['type'] == 'real') 'type': 'real',
            // A static file timestamp belongs to one user. For the endpoint,
            // ts=1 only asks UCenter to resolve the target's own timestamp.
            if (target == _currentUserId && query['ts'] == '1') 'ts': '1',
          },
          fragment: '',
        ),
      );
    }

    // Do not propagate signed/plugin query strings to another user's file.
    if (!{'ts', 'random'}.containsAll(query.keys)) return null;
    final match = _staticPath.firstMatch(avatar.path);
    String root;
    var real = '';
    if (match != null) {
      final encodedUid = '${match[2]}${match[3]}${match[4]}${match[5]}';
      if (encodedUid != _currentUserId.padLeft(9, '0')) return null;
      root = match[1]!;
      real = match[6] ?? '';
    } else if (avatar.path.endsWith('/noavatar.svg')) {
      // This proves only that the current user has no avatar, not that every
      // other user should display the same default.
      if (target == _currentUserId) {
        return _validated(avatar.replace(query: '', fragment: ''));
      }
      root = avatar.path.substring(0, avatar.path.lastIndexOf('/') + 1);
    } else {
      return null;
    }

    final padded = target.padLeft(9, '0');
    return _validated(
      avatar.replace(
        path:
            '$root${padded.substring(0, 3)}/${padded.substring(3, 5)}/'
            '${padded.substring(5, 7)}/${padded.substring(7)}'
            '${real}_avatar_middle.jpg',
        queryParameters: {
          if (target == _currentUserId && query['ts'] != null)
            'ts': query['ts']!,
        },
        fragment: '',
      ),
    );
  }

  String? _validated(Uri uri) {
    // An empty query is not part of the asset's identity (avoid a trailing ?).
    final normalized = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: uri.query.isEmpty ? null : uri.query,
    );
    return _resources.resolve(normalized.toString())?.uri.toString();
  }
}
