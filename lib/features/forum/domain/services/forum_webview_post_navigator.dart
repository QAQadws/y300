import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

final forumWebViewPostNavigatorProvider = Provider<ForumWebViewPostNavigator>((
  ref,
) {
  return ForumWebViewPostNavigator(
    webViewNavigator: ref.read(forumWebViewNavigatorProvider),
  );
});

/// 把 WebView 中点到的"发新帖" URL 翻译成 [ForumWebViewPostRequest]，
/// 让 forum_webview_page 把它推到我们自己的 PostingComposerPage。
///
/// 与 [forum_webview_reply_navigator.dart] 同构：
/// - 仅在站内（`isManagedSite`）+ `forum.php` 路径上识别。
/// - 兼容 `&amp;` HTML 转义（WebView 拦截到的 URL 偶尔会带）。
/// - `mod=post & action=newthread & fid=N` 三件齐了才返回 request；缺 fid
///   或站外 / 其它 mod 都返回 null（让上层决定是 navigate 还是放行外链）。
class ForumWebViewPostNavigator {
  const ForumWebViewPostNavigator({
    required ForumWebViewNavigator webViewNavigator,
  }) : _webViewNavigator = webViewNavigator;

  final ForumWebViewNavigator _webViewNavigator;

  ForumWebViewPostRequest? resolveNewThread(String rawUrl) {
    final uri = _webViewNavigator.resolve(rawUrl.replaceAll('&amp;', '&'));
    if (!_webViewNavigator.isManagedSite(uri) ||
        !uri.path.endsWith('/forum.php')) {
      return null;
    }
    final query = uri.queryParameters;
    if (query['mod'] != 'post' || query['action'] != 'newthread') {
      return null;
    }
    final fid = _normalize(query['fid']);
    if (fid == null) {
      return null;
    }
    return ForumWebViewPostRequest(fid: fid, sourceUri: uri);
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

/// 拦截命中后回传给页面层用来 push PostingComposerPage 的请求对象。
///
/// `sourceUri` 仅作埋点 / 排错；提交载荷的 `fid` 才是 controller 用到的字段。
class ForumWebViewPostRequest {
  const ForumWebViewPostRequest({required this.fid, required this.sourceUri});

  final String fid;
  final Uri sourceUri;
}
