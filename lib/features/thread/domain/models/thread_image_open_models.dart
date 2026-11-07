import 'package:y300/features/thread/domain/models/thread_image_layout_hint.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

class ThreadPostImageGroup {
  const ThreadPostImageGroup({
    required this.tid,
    required this.pid,
    required this.postNumber,
    required this.entries,
  });

  final String tid;
  final String pid;
  final int postNumber;
  final List<ThreadPostImageEntry> entries;

  List<String> get urls =>
      entries.map((entry) => entry.url).toList(growable: false);
}

class ThreadPostImageEntry {
  const ThreadPostImageEntry({
    required this.url,
    required this.rawUrl,
    required this.indexInPost,
    required this.cacheKey,
    this.aid,
    this.layoutHint,
  });

  final String url;
  final String rawUrl;

  /// Original occurrence in the body, which can differ from gallery position.
  final int indexInPost;
  final String cacheKey;
  final String? aid;
  final ThreadPostBlockImageLayoutHint? layoutHint;
}

class ThreadImageOpenRequest {
  const ThreadImageOpenRequest({
    required this.tid,
    required this.pid,
    required this.postNumber,
    required this.referer,
    required this.group,
    required this.initialIndex,
    this.pollOptionId,
    this.continuousImages = const <ContinuousImageItem>[],
  });

  final String tid;
  final String pid;
  final int postNumber;
  final String referer;

  /// Null identifies the post body; otherwise this gallery belongs to one
  /// actual poll option in the same post, with its own occurrence ordinals.
  final String? pollOptionId;
  String get sourceOwnerId =>
      'thread:$tid:post:$pid${pollOptionId == null ? '' : ':poll:${Uri.encodeComponent(pollOptionId!)}'}';
  final ThreadPostImageGroup group;

  /// Position in the gallery's filtered entries.
  final int initialIndex;
  final List<ContinuousImageItem> continuousImages;

  ThreadPostImageEntry? get initialEntry {
    if (initialIndex < 0 || initialIndex >= group.entries.length) {
      return null;
    }
    return group.entries[initialIndex];
  }
}
