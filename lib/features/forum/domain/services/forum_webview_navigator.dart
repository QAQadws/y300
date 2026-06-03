import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';

final forumWebViewNavigatorProvider = Provider<ForumWebViewNavigator>((ref) {
  return DefaultForumWebViewNavigator();
});

abstract class ForumWebViewNavigator {
  Uri get homeUri;

  Uri resolve(String raw);

  ForumWebViewPageKind classify(Uri uri);

  String? extractFid(Uri uri);

  String? extractTid(Uri uri);

  bool isManagedSite(Uri uri);
}

class DefaultForumWebViewNavigator implements ForumWebViewNavigator {
  DefaultForumWebViewNavigator()
      : _siteRoot = Uri.parse('${AppConfig.siteBaseUrl}/'),
        _siteHost = Uri.parse(AppConfig.siteBaseUrl).host;

  final Uri _siteRoot;
  final String _siteHost;

  @override
  Uri get homeUri => _siteRoot.resolve('index.php?mobile=2');

  @override
  ForumWebViewPageKind classify(Uri uri) {
    if (!isManagedSite(uri)) {
      return ForumWebViewPageKind.other;
    }

    final path = uri.path;
    final mod = uri.queryParameters['mod'];
    final mobile = uri.queryParameters['mobile'];

    if (path.endsWith('/index.php') && mobile == '2') {
      return ForumWebViewPageKind.home;
    }

    if (path.endsWith('/forum.php') && mod == 'forumdisplay') {
      return ForumWebViewPageKind.forumDisplay;
    }

    if (path.endsWith('/forum.php') && mod == 'viewthread') {
      return ForumWebViewPageKind.threadDetail;
    }

    if (path.endsWith('/search.php') && mod == 'forum') {
      return ForumWebViewPageKind.search;
    }

    return ForumWebViewPageKind.other;
  }

  @override
  String? extractFid(Uri uri) {
    final kind = classify(uri);
    if (kind != ForumWebViewPageKind.forumDisplay &&
        kind != ForumWebViewPageKind.threadDetail) {
      return null;
    }
    return _normalizeQueryValue(uri.queryParameters['fid']);
  }

  @override
  String? extractTid(Uri uri) {
    if (classify(uri) != ForumWebViewPageKind.threadDetail) {
      return null;
    }
    return _normalizeQueryValue(uri.queryParameters['tid']);
  }

  @override
  bool isManagedSite(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    return host.isNotEmpty && host == _siteHost;
  }

  @override
  Uri resolve(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return _siteRoot;
    }

    if (trimmed.startsWith('//')) {
      return Uri.parse('https:$trimmed');
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return _siteRoot;
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    return _siteRoot.resolveUri(parsed);
  }

  String? _normalizeQueryValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
