import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
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
    this.continuousImages = const <ContinuousImageItem>[],
  });

  final String tid;
  final String pid;
  final int postNumber;
  final String referer;
  final ThreadPostImageGroup group;
  final int initialIndex;
  final List<ContinuousImageItem> continuousImages;

  ThreadPostImageEntry? get initialEntry {
    if (initialIndex < 0 || initialIndex >= group.entries.length) {
      return null;
    }
    return group.entries[initialIndex];
  }
}

class ThreadImageOpenContext {
  const ThreadImageOpenContext({
    required this.tid,
    required this.pid,
    required this.postNumber,
    required this.referer,
    required this.cacheKeyForImage,
  });

  final String tid;
  final String pid;
  final int postNumber;
  final String referer;
  final String Function(ThreadPostImageBlock image) cacheKeyForImage;
}
