import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';

/// Transient bridge between one native thread page and its image reader.
/// Layout anchors belong to the renderer; no reading progress is persisted.
final class ThreadImageReaderReturnCoordinator {
  ThreadImageReaderReturnCoordinator({required this.scrollController});

  final ScrollController scrollController;
  final _bodies = <String, _ImageReturnBody>{};
  String? _tid;
  int? _page;
  int _generation = 0;
  bool _disposed = false;

  void updatePage({
    required String tid,
    required int page,
    required Map<String, String> bodyHtmlByPid,
  }) {
    if (_disposed) return;
    if (_tid != tid || _page != page) {
      _clear();
      _tid = tid;
      _page = page;
    }
    _bodies.removeWhere((pid, body) {
      if (bodyHtmlByPid[pid] == body.html) return false;
      body.anchors.dispose();
      return true;
    });
    for (final entry in bodyHtmlByPid.entries) {
      _bodies.putIfAbsent(entry.key, () => _ImageReturnBody(entry.value));
    }
  }

  ForumHtmlImageAnchorController? anchorsFor(String pid) =>
      _disposed ? null : _bodies[pid]?.anchors;

  Future<void> Function(ThreadImageReaderExitResult)? beforeExitFor(
    ThreadImageOpenRequest request,
  ) {
    final body = _bodies[request.pid];
    if (_disposed || request.tid != _tid || body == null) return null;
    final entries = List<ThreadPostImageEntry>.unmodifiable(
      request.group.entries,
    );
    final initialIndexInPost = request.initialEntry?.indexInPost;
    final generation = ++_generation;
    bool isCurrent() =>
        !_disposed &&
        generation == _generation &&
        request.tid == _tid &&
        identical(_bodies[request.pid], body);
    return (result) async {
      if (!isCurrent() ||
          result.tid != request.tid ||
          result.pid != request.pid ||
          result.indexInPost == initialIndexInPost) {
        return;
      }
      // Index is authoritative, including repeated URLs. Verify against the
      // originating snapshot so a changed image group cannot redirect exit.
      final matching = entries.where(
        (entry) =>
            entry.indexInPost == result.indexInPost &&
            entry.cacheKey == result.cacheKey &&
            entry.url == result.url,
      );
      if (matching.length != 1) return;
      await body.anchors.revealImage(
        index: result.indexInPost,
        cacheKey: result.cacheKey,
        url: result.url,
        scrollController: scrollController,
        isCurrent: isCurrent,
      );
    };
  }

  void dispose() {
    _disposed = true;
    _clear();
  }

  void _clear() {
    _generation++;
    for (final body in _bodies.values) {
      body.anchors.dispose();
    }
    _bodies.clear();
  }
}

final class _ImageReturnBody {
  _ImageReturnBody(this.html);

  final String html;
  final anchors = ForumHtmlImageAnchorController();
}
