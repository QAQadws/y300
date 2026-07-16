import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

final forumWebViewThreadDocumentBridgeProvider =
    Provider<ForumWebViewThreadDocumentBridge>((ref) {
      return const DefaultForumWebViewThreadDocumentBridge();
    });

abstract class ForumWebViewThreadDocumentTarget {
  Future<Object?> runJavaScriptReturningResult(String script);
}

abstract class ForumWebViewThreadDocumentBridge {
  String get extractScript;

  Future<ForumThreadDocumentSnapshot?> read({
    required ForumWebViewThreadDocumentTarget target,
    required ForumWebViewNavigator navigator,
  });
}

class DefaultForumWebViewThreadDocumentBridge
    implements ForumWebViewThreadDocumentBridge {
  const DefaultForumWebViewThreadDocumentBridge();

  @override
  String get extractScript => '''
(() => {
  const normalizeText = (value) =>
    (value || '').replace(/\\s+/g, ' ').trim();
  const mobilePosts = Array.from(
    document.querySelectorAll('.viewthread .plc[id^="pid"]'),
  );
  const desktopPosts = Array.from(
    document.querySelectorAll('#postlist > div[id^="post_"]'),
  );
  const posts = mobilePosts.length > 0 ? mobilePosts : desktopPosts;
  const titleNode =
    document.querySelector('.viewthread .view_tit') ||
    document.querySelector('#thread_subject') ||
    document.querySelector('.viewthread_title');
  let title = null;
  if (titleNode) {
    const clone = titleNode.cloneNode(true);
    clone.querySelectorAll('em').forEach((node) => node.remove());
    title = normalizeText(clone.textContent) || null;
  }
  const canonical = document.querySelector('link[rel="canonical"]');
  const forumLinks = Array.from(document.querySelectorAll(
    '.header h2 a[href*="forumdisplay"], '
    + '#pt a[href*="forumdisplay"], #pt a[href*="forum-"]',
  ));
  const forumLink = forumLinks.length > 0
    ? forumLinks[forumLinks.length - 1]
    : null;
  const firstPost = posts.find((post) => {
    if (post.querySelector('.display.pione')) {
      return true;
    }
    const floorLabel = normalizeText(
      (post.querySelector('.authi .mtit .y, .pi strong a em') || {}).textContent,
    );
    return floorLabel === '1' || floorLabel === '1#' ||
      floorLabel === '1楼' || floorLabel === '楼主';
  }) || null;
  const firstPostBody = firstPost
    ? firstPost.querySelector('.message, [id^="postmessage_"], td.t_f')
    : null;
  const firstPostImage = firstPostBody
    ? Array.from(firstPostBody.querySelectorAll('img')).find((image) => {
        const source = normalizeText(
          image.getAttribute('data-original') ||
          image.getAttribute('data-src') ||
          image.getAttribute('file') ||
          image.getAttribute('src'),
        );
        return source && !/(smilies|static[/]image|emotion|avatar|uc_server[/]data[/]avatar)/i.test(source);
      }) || null
    : null;
  const payload = {
    title,
    forumName: forumLink ? normalizeText(forumLink.textContent) || null : null,
    canonicalHref: canonical
      ? normalizeText(canonical.getAttribute('href')) || null
      : null,
    firstPostImageHref: firstPostImage
      ? normalizeText(
          firstPostImage.getAttribute('data-original') ||
          firstPostImage.getAttribute('data-src') ||
          firstPostImage.getAttribute('file') ||
          firstPostImage.getAttribute('src'),
        ) || null
      : null,
    postCount: posts.length,
    authorOnlyHref: null,
    normalThreadHref: null,
    reverseOrderHref: null,
    normalOrderHref: null,
  };
  const items = document.querySelectorAll(
    '#nav-more-menu .nav-more-item',
  );
  for (const item of items) {
    const label = normalizeText(item.textContent);
    const href = normalizeText(item.getAttribute('href'));
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
  Future<ForumThreadDocumentSnapshot?> read({
    required ForumWebViewThreadDocumentTarget target,
    required ForumWebViewNavigator navigator,
  }) async {
    final raw = await target.runJavaScriptReturningResult(extractScript);
    final payload = _decodePayload(raw);
    if (payload == null) {
      return null;
    }

    return ForumThreadDocumentSnapshot(
      title: _normalizeText(payload['title']),
      forumName: _normalizeText(payload['forumName']),
      canonicalUri: _resolveManagedUri(
        payload['canonicalHref'],
        navigator: navigator,
      ),
      firstPostImageUrl: _resolveHttpUri(
        payload['firstPostImageHref'],
        navigator: navigator,
      )?.toString(),
      postCount: _parseNonNegativeInt(payload['postCount']),
      menu: ForumThreadMenuSnapshot(
        authorOnlyUri: _resolveManagedUri(
          payload['authorOnlyHref'],
          navigator: navigator,
        ),
        normalThreadUri: _resolveManagedUri(
          payload['normalThreadHref'],
          navigator: navigator,
        ),
        reverseOrderUri: _resolveManagedUri(
          payload['reverseOrderHref'],
          navigator: navigator,
        ),
        normalOrderUri: _resolveManagedUri(
          payload['normalOrderHref'],
          navigator: navigator,
        ),
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
      return decoded.map((key, value) => MapEntry(key.toString(), value));
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

  Uri? _resolveManagedUri(
    Object? rawHref, {
    required ForumWebViewNavigator navigator,
  }) {
    final uri = _resolveHttpUri(rawHref, navigator: navigator);
    if (uri == null || !navigator.isManagedSite(uri)) {
      return null;
    }
    return uri;
  }

  Uri? _resolveHttpUri(
    Object? rawHref, {
    required ForumWebViewNavigator navigator,
  }) {
    final href = _normalizeText(rawHref);
    if (href == null || href.toLowerCase().startsWith('javascript:')) {
      return null;
    }
    final uri = navigator.resolve(href.replaceAll('&amp;', '&'));
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  String? _normalizeText(Object? value) {
    final normalized = value?.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  int _parseNonNegativeInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString().trim() ?? '');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }
}
