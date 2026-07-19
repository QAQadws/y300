import 'package:y300/core/config/app_config.dart';

abstract interface class ForumAvatarUrlBuilder {
  Uri? buildMiddleAvatar(String authorId);
}

class DefaultForumAvatarUrlBuilder implements ForumAvatarUrlBuilder {
  const DefaultForumAvatarUrlBuilder();

  static final Uri _siteBase = Uri.parse(AppConfig.siteBaseUrl);

  @override
  Uri? buildMiddleAvatar(String authorId) {
    final raw = authorId.trim();
    if (raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw) || raw.length > 9) {
      return null;
    }

    final normalized = raw.padLeft(9, '0');
    final first = normalized.substring(0, 3);
    final second = normalized.substring(3, 5);
    final third = normalized.substring(5, 7);
    final fourth = normalized.substring(7, 9);
    return _siteBase.replace(
      path:
          '/uc_server/data/avatar/$first/$second/$third/'
          '${fourth}_avatar_middle.jpg',
    );
  }
}
