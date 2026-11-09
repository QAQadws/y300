import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Current visible content, without the page controller or its unrelated state.
final class ThreadPostLoadingContent {
  const ThreadPostLoadingContent({
    required this.tid,
    required this.posts,
    required this.supportsRatings,
  });

  final String tid;
  final List<ThreadPost> posts;
  final bool supportsRatings;

  ThreadPost? findPost(String pid) {
    for (final post in posts) {
      if (post.pid.trim() == pid) return post;
    }
    return null;
  }
}
