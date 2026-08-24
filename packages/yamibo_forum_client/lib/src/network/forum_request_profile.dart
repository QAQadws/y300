import '../client/forum_client_config.dart';

enum ForumRequestProfileKind { mobileHtml, desktopHtml, discuzApi, resource }

final class ForumRequestProfile {
  const ForumRequestProfile({required this.kind, required this.headers});

  final ForumRequestProfileKind kind;
  final Map<String, String> headers;
}

abstract interface class ForumRequestProfileResolver {
  ForumRequestProfile resolve(ForumRequestProfileKind kind, {Uri? referer});
}

final class DefaultForumRequestProfileResolver
    implements ForumRequestProfileResolver {
  const DefaultForumRequestProfileResolver(this.config);

  final ForumClientConfig config;

  @override
  ForumRequestProfile resolve(ForumRequestProfileKind kind, {Uri? referer}) {
    final userAgent = switch (kind) {
      ForumRequestProfileKind.mobileHtml => config.mobileUserAgent,
      ForumRequestProfileKind.desktopHtml => config.effectiveDesktopUserAgent,
      ForumRequestProfileKind.discuzApi => config.effectiveApiUserAgent,
      ForumRequestProfileKind.resource => config.mobileUserAgent,
    };
    final accept = switch (kind) {
      ForumRequestProfileKind.discuzApi => 'application/json,text/plain,*/*',
      ForumRequestProfileKind.resource =>
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      _ => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
    return ForumRequestProfile(
      kind: kind,
      headers: <String, String>{
        'User-Agent': userAgent,
        'Accept': accept,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        if (kind != ForumRequestProfileKind.resource) ...const {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
        if (referer != null) 'Referer': referer.toString(),
      },
    );
  }
}
