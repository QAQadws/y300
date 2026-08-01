import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';

final forumWebViewReplyNavigatorProvider = Provider<ForumWebViewReplyNavigator>(
  (ref) {
    return ForumWebViewReplyNavigator(
      webViewNavigator: ref.read(forumWebViewNavigatorProvider),
    );
  },
);

class ForumWebViewReplyNavigator {
  const ForumWebViewReplyNavigator({
    required ForumWebViewNavigator webViewNavigator,
  }) : _webViewNavigator = webViewNavigator;

  final ForumWebViewNavigator _webViewNavigator;

  ForumWebViewPostReplyRequest? resolvePostReply(String rawUrl) {
    final uri = _webViewNavigator.resolve(rawUrl.replaceAll('&amp;', '&'));
    if (!_webViewNavigator.isManagedSite(uri) ||
        !uri.path.endsWith('/forum.php')) {
      return null;
    }
    final query = uri.queryParameters;
    if (query['mod'] != 'post' || query['action'] != 'reply') {
      return null;
    }
    final fid = _normalize(query['fid']);
    final tid = _normalize(query['tid']);
    final repquote = _normalize(query['repquote']);
    if (fid == null || tid == null || repquote == null) {
      return null;
    }
    return ForumWebViewPostReplyRequest(
      fid: fid,
      tid: tid,
      repquote: repquote,
      replyFormUri: uri,
    );
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class ForumWebViewPostReplyRequest {
  const ForumWebViewPostReplyRequest({
    required this.fid,
    required this.tid,
    required this.repquote,
    required this.replyFormUri,
  });

  final String fid;
  final String tid;
  final String repquote;
  final Uri replyFormUri;
}
