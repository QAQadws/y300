import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

final forumWebViewThreadLinkRouterProvider =
    Provider<ForumWebViewThreadLinkRouter>((ref) {
      return ForumWebViewThreadLinkRouter(
        navigator: ref.read(forumWebViewNavigatorProvider),
      );
    });

enum ForumWebViewThreadLinkKind {
  none,
  thread,
  threadPost,
  findPostRedirect,
  emptyFindPostRedirect,
}

class ForumWebViewThreadLinkResolution {
  const ForumWebViewThreadLinkResolution({
    required this.kind,
    required this.originalUri,
    required this.normalizedUri,
    this.tid,
    this.pid,
    this.page,
  });

  final ForumWebViewThreadLinkKind kind;
  final Uri originalUri;
  final Uri normalizedUri;
  final String? tid;
  final String? pid;
  final int? page;

  bool get isThreadLink => kind != ForumWebViewThreadLinkKind.none;
}

class ForumWebViewThreadLinkRouter {
  const ForumWebViewThreadLinkRouter({required ForumWebViewNavigator navigator})
    : _navigator = navigator;

  final ForumWebViewNavigator _navigator;

  ForumWebViewThreadLinkResolution resolve(String rawUrl) {
    final originalUri = _navigator.resolve(rawUrl.replaceAll('&amp;', '&'));
    if (!_navigator.isManagedSite(originalUri)) {
      return ForumWebViewThreadLinkResolution(
        kind: ForumWebViewThreadLinkKind.none,
        originalUri: originalUri,
        normalizedUri: originalUri,
      );
    }

    final normalizedUri = _withMobileParam(originalUri);
    final path = normalizedUri.path.toLowerCase();
    final query = normalizedUri.queryParameters;
    if (!path.endsWith('/forum.php')) {
      return ForumWebViewThreadLinkResolution(
        kind: ForumWebViewThreadLinkKind.none,
        originalUri: originalUri,
        normalizedUri: normalizedUri,
      );
    }

    final mod = query['mod']?.trim().toLowerCase();
    if (mod == 'viewthread') {
      final tid = _normalize(query['tid']);
      if (tid == null) {
        return ForumWebViewThreadLinkResolution(
          kind: ForumWebViewThreadLinkKind.none,
          originalUri: originalUri,
          normalizedUri: normalizedUri,
        );
      }
      final pid = _extractFragmentPid(normalizedUri);
      return ForumWebViewThreadLinkResolution(
        kind: pid == null
            ? ForumWebViewThreadLinkKind.thread
            : ForumWebViewThreadLinkKind.threadPost,
        originalUri: originalUri,
        normalizedUri: normalizedUri,
        tid: tid,
        pid: pid,
        page: _parsePositiveInt(query['page']),
      );
    }

    final goto = query['goto']?.trim().toLowerCase();
    if (mod == 'redirect' && goto == 'findpost') {
      final tid = _normalize(query['ptid']);
      if (tid == null) {
        return ForumWebViewThreadLinkResolution(
          kind: ForumWebViewThreadLinkKind.none,
          originalUri: originalUri,
          normalizedUri: normalizedUri,
        );
      }
      final pid = _normalize(query['pid']);
      return ForumWebViewThreadLinkResolution(
        kind: pid == null
            ? ForumWebViewThreadLinkKind.emptyFindPostRedirect
            : ForumWebViewThreadLinkKind.findPostRedirect,
        originalUri: originalUri,
        normalizedUri: normalizedUri,
        tid: tid,
        pid: pid,
      );
    }

    return ForumWebViewThreadLinkResolution(
      kind: ForumWebViewThreadLinkKind.none,
      originalUri: originalUri,
      normalizedUri: normalizedUri,
    );
  }

  Uri _withMobileParam(Uri uri) {
    final query = <String, String>{};
    for (final segment in uri.query.split(RegExp(r'[&;]'))) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final rawKey = separator < 0 ? segment : segment.substring(0, separator);
      final rawValue = separator < 0 ? '' : segment.substring(separator + 1);
      final key = _decodeQueryComponent(rawKey);
      final value = _decodeQueryComponent(rawValue);
      if (key == null ||
          key.trim().isEmpty ||
          value == null ||
          value.trim().isEmpty) {
        continue;
      }
      query[key] = value;
    }
    query['mobile'] = '2';
    return uri.replace(queryParameters: query);
  }

  String? _decodeQueryComponent(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on FormatException {
      return null;
    }
  }

  String? _extractFragmentPid(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }
    return RegExp(
      r'pid(\d+)',
      caseSensitive: false,
    ).firstMatch(fragment)?.group(1);
  }

  int? _parsePositiveInt(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
