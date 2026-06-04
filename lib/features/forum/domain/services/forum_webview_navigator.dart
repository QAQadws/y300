import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';

final forumWebViewNavigatorProvider = Provider<ForumWebViewNavigator>((ref) {
  return DefaultForumWebViewNavigator();
});

abstract class ForumWebViewNavigator {
  Uri get homeUri;

  Uri forumSearchUri();

  Uri curForumSearchUri({required String fid});

  Uri resolve(String raw);

  ForumWebViewPageKind classify(Uri uri);

  ForumWebViewSearchScope? extractSearchScope(Uri uri);

  String? extractSearchFid(Uri uri);

  String? extractFid(Uri uri);

  String? extractTid(Uri uri);

  String? extractAuthorId(Uri uri);

  bool isReverseOrder(Uri uri);

  Uri buildAuthorOnlyUri({required Uri currentUri, required String authorId});

  Uri buildNormalThreadUri(Uri currentUri);

  Uri buildReverseOrderUri(Uri currentUri);

  Uri buildNormalOrderUri(Uri currentUri);

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
  Uri forumSearchUri() => _siteRoot.resolve('search.php?mod=forum&mobile=2');

  @override
  Uri curForumSearchUri({required String fid}) {
    return _siteRoot.resolve('search.php?mod=curforum&srhfid=$fid&mobile=2');
  }

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

    if (path.endsWith('/search.php') &&
        (mod == 'forum' || mod == 'curforum')) {
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
  String? extractAuthorId(Uri uri) {
    if (classify(uri) != ForumWebViewPageKind.threadDetail) {
      return null;
    }
    return _normalizeQueryValue(uri.queryParameters['authorid']);
  }

  @override
  bool isReverseOrder(Uri uri) {
    if (classify(uri) != ForumWebViewPageKind.threadDetail) {
      return false;
    }
    return _normalizeQueryValue(uri.queryParameters['ordertype']) == '1';
  }

  @override
  ForumWebViewSearchScope? extractSearchScope(Uri uri) {
    if (classify(uri) != ForumWebViewPageKind.search) {
      return null;
    }
    final mod = uri.queryParameters['mod']?.trim();
    if (mod == 'curforum') {
      return ForumWebViewSearchScope.curForum;
    }
    if (mod == 'forum') {
      final hasSearchId = _normalizeQueryValue(uri.queryParameters['searchid']);
      if (hasSearchId != null &&
          _normalizeQueryValue(uri.queryParameters['srhfid']) == null) {
        return null;
      }
      return ForumWebViewSearchScope.forum;
    }
    return null;
  }

  @override
  String? extractSearchFid(Uri uri) {
    if (classify(uri) != ForumWebViewPageKind.search) {
      return null;
    }
    return _normalizeQueryValue(uri.queryParameters['srhfid']);
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

  @override
  Uri buildAuthorOnlyUri({required Uri currentUri, required String authorId}) {
    final params = _copyQueryParameters(currentUri);
    params['authorid'] = authorId;
    return _replaceQueryParameters(currentUri, params);
  }

  @override
  Uri buildNormalThreadUri(Uri currentUri) {
    final params = _copyQueryParameters(currentUri);
    params.remove('authorid');
    return _replaceQueryParameters(currentUri, params);
  }

  @override
  Uri buildReverseOrderUri(Uri currentUri) {
    final params = _copyQueryParameters(currentUri);
    params['ordertype'] = '1';
    return _replaceQueryParameters(currentUri, params);
  }

  @override
  Uri buildNormalOrderUri(Uri currentUri) {
    final params = _copyQueryParameters(currentUri);
    params.remove('ordertype');
    return _replaceQueryParameters(currentUri, params);
  }

  Map<String, String> _copyQueryParameters(Uri uri) {
    return Map<String, String>.from(resolve(uri.toString()).queryParameters);
  }

  Uri _replaceQueryParameters(Uri currentUri, Map<String, String> params) {
    final absoluteUri = resolve(currentUri.toString());
    return absoluteUri.replace(queryParameters: params);
  }

  String? _normalizeQueryValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
