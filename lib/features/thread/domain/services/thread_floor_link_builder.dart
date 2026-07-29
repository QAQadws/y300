import 'package:y300/core/config/app_config.dart';

/// Builds the stable Discuz redirect URL for a specific post.
///
/// The thread/post identifiers are the only values that identify a floor.
/// `fromuid` is an optional promotion attribution parameter and is included
/// only when the current session provides a valid positive user id.
final class ThreadFloorLinkBuilder {
  ThreadFloorLinkBuilder({Uri? siteBaseUri})
    : _siteBaseUri = siteBaseUri ?? Uri.parse(AppConfig.siteBaseUrl);

  static final RegExp _positiveInteger = RegExp(r'^[1-9][0-9]*$');

  final Uri _siteBaseUri;

  Uri? build({required String tid, required String pid, String? fromUid}) {
    final normalizedTid = tid.trim();
    final normalizedPid = pid.trim();
    if (!_isPositiveInteger(normalizedTid) ||
        !_isPositiveInteger(normalizedPid)) {
      return null;
    }

    final normalizedFromUid = fromUid?.trim();
    return _siteBaseUri.replace(
      path: '/forum.php',
      queryParameters: <String, String>{
        'mod': 'redirect',
        'goto': 'findpost',
        'ptid': normalizedTid,
        'pid': normalizedPid,
        if (normalizedFromUid != null && _isPositiveInteger(normalizedFromUid))
          'fromuid': normalizedFromUid,
      },
    );
  }

  bool _isPositiveInteger(String value) => _positiveInteger.hasMatch(value);
}
