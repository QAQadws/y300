import '../client/forum_client_config.dart';

/// Browser identity profiles used by forum requests.
enum ForumRequestProfileKind {
  /// Mobile-layout HTML request.
  mobileHtml,

  /// Desktop-layout HTML request.
  desktopHtml,

  /// Discuz mobile API request.
  discuzApi,

  /// Protected image resource request.
  resource,
}

/// Sanitized request headers for one [ForumRequestProfileKind].
final class ForumRequestProfile {
  /// Creates a [ForumRequestProfile].
  const ForumRequestProfile({required this.kind, required this.headers});

  /// Identity category represented by these headers.
  final ForumRequestProfileKind kind;

  /// Headers safe to attach to the matching request category.
  final Map<String, String> headers;
}

/// Resolves browser identity headers at the transport boundary.
abstract interface class ForumRequestProfileResolver {
  /// Resolves headers for [kind], optionally using [referer].
  ForumRequestProfile resolve(ForumRequestProfileKind kind, {Uri? referer});
}

/// Default resolver backed by [ForumClientConfig].
final class DefaultForumRequestProfileResolver
    implements ForumRequestProfileResolver {
  /// Creates a [DefaultForumRequestProfileResolver].
  const DefaultForumRequestProfileResolver(this.config);

  /// Client origins and browser identities used to build request headers.
  final ForumClientConfig config;

  @override
  ForumRequestProfile resolve(ForumRequestProfileKind kind, {Uri? referer}) {
    final userAgent = switch (kind) {
      ForumRequestProfileKind.mobileHtml => config.mobileUserAgent,
      ForumRequestProfileKind.desktopHtml => config.effectiveDesktopUserAgent,
      ForumRequestProfileKind.discuzApi => config.effectiveApiUserAgent,
      ForumRequestProfileKind.resource => config.effectiveResourceUserAgent,
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
