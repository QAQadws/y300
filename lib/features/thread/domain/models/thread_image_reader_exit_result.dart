/// Transient position returned by a thread image reader to its originating body.
///
/// The image identity comes from the opening snapshot. It is deliberately not a
/// persisted reading record: the caller must verify it against the current post.
class ThreadImageReaderExitResult {
  const ThreadImageReaderExitResult({
    required this.tid,
    required this.pid,
    required this.indexInPost,
    required this.cacheKey,
    required this.url,
  });

  final String tid;
  final String pid;
  final int indexInPost;
  final String cacheKey;
  final String url;

  @override
  bool operator ==(Object other) {
    return other is ThreadImageReaderExitResult &&
        other.tid == tid &&
        other.pid == pid &&
        other.indexInPost == indexInPost &&
        other.cacheKey == cacheKey &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(tid, pid, indexInPost, cacheKey, url);
}
