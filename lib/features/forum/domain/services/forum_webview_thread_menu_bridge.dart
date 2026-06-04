import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

final forumWebViewThreadMenuBridgeProvider = Provider<ForumWebViewThreadMenuBridge>(
  (ref) {
    return const DefaultForumWebViewThreadMenuBridge();
  },
);

abstract class ForumWebViewThreadMenuTarget {
  Future<Object?> runJavaScriptReturningResult(String script);
}

abstract class ForumWebViewThreadMenuBridge {
  String get extractScript;

  Future<ForumThreadMenuSnapshot?> read({
    required ForumWebViewThreadMenuTarget target,
    required ForumWebViewNavigator navigator,
  });
}

class DefaultForumWebViewThreadMenuBridge
    implements ForumWebViewThreadMenuBridge {
  const DefaultForumWebViewThreadMenuBridge();

  @override
  String get extractScript => '''
(() => {
  const items = document.querySelectorAll('#nav-more-menu .nav-more-item');
  const payload = {
    authorOnlyHref: null,
    normalThreadHref: null,
    reverseOrderHref: null,
    normalOrderHref: null,
  };
  for (const item of items) {
    const label = (item.textContent || '').replace(/\\s+/g, ' ').trim();
    const href = (item.getAttribute('href') || '').trim();
    if (!label || !href || href.toLowerCase().startsWith('javascript:')) {
      continue;
    }
    switch (label) {
      case '只看楼主':
        payload.authorOnlyHref = href;
        break;
      case '看全部':
        payload.normalThreadHref = href;
        break;
      case '倒序浏览':
        payload.reverseOrderHref = href;
        break;
      case '正序浏览':
        payload.normalOrderHref = href;
        break;
    }
  }
  return JSON.stringify(payload);
})();
''';

  @override
  Future<ForumThreadMenuSnapshot?> read({
    required ForumWebViewThreadMenuTarget target,
    required ForumWebViewNavigator navigator,
  }) async {
    final raw = await target.runJavaScriptReturningResult(extractScript);
    final payload = _decodePayload(raw);
    if (payload == null) {
      return null;
    }

    return ForumThreadMenuSnapshot(
      authorOnlyUri: _resolveHref(
        payload['authorOnlyHref'],
        navigator: navigator,
      ),
      normalThreadUri: _resolveHref(
        payload['normalThreadHref'],
        navigator: navigator,
      ),
      reverseOrderUri: _resolveHref(
        payload['reverseOrderHref'],
        navigator: navigator,
      ),
      normalOrderUri: _resolveHref(
        payload['normalOrderHref'],
        navigator: navigator,
      ),
    );
  }

  Map<String, Object?>? _decodePayload(Object? raw) {
    final jsonText = _normalizeJsonText(raw);
    if (jsonText == null) {
      return null;
    }

    final decoded = jsonDecode(jsonText);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map<Object?, Object?>) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return null;
  }

  String? _normalizeJsonText(Object? raw) {
    if (raw == null) {
      return null;
    }

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == 'null') {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String) {
          return decoded;
        }
        return jsonEncode(decoded);
      } catch (_) {
        return trimmed;
      }
    }

    return jsonEncode(raw);
  }

  Uri? _resolveHref(
    Object? rawHref, {
    required ForumWebViewNavigator navigator,
  }) {
    final href = (rawHref as String?)?.trim();
    if (href == null || href.isEmpty) {
      return null;
    }
    if (href.toLowerCase().startsWith('javascript:')) {
      return null;
    }

    final uri = navigator.resolve(href.replaceAll('&amp;', '&'));
    if (!navigator.isManagedSite(uri)) {
      return null;
    }
    return uri;
  }
}
