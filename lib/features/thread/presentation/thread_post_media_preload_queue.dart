import 'dart:async';

import 'package:y300/features/cache/domain/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';

class ThreadResourcePrewarmTask {
  const ThreadResourcePrewarmTask({
    required this.tid,
    required this.plan,
    required this.segmentIndex,
    this.lookAheadSegments = 1,
    this.maxRequests = 2,
  }) : assert(lookAheadSegments >= 0),
       assert(maxRequests > 0);

  final String tid;
  final ThreadPostBodyRenderPlan plan;
  final int segmentIndex;
  final int lookAheadSegments;
  final int maxRequests;
}

/// A deliberately mild prewarm queue for the native thread reader.
///
/// It consumes already-built render plans instead of parsing far-away posts, and
/// it only ensures cache files. Layout hints and visible widgets are not updated
/// from this queue, so prewarming cannot trigger current scroll reflow.
class ThreadPostMediaPreloadQueue {
  ThreadPostMediaPreloadQueue({
    required ImageCacheService imageCacheService,
    this.maxConcurrent = 1,
  }) : _imageCacheService = imageCacheService,
       assert(maxConcurrent > 0);

  final ImageCacheService _imageCacheService;
  final int maxConcurrent;

  final Set<String> _queuedOrDone = <String>{};
  final List<ImageCacheRequest> _pending = <ImageCacheRequest>[];
  var _running = 0;
  var _paused = false;
  var _disposed = false;

  void dispose() {
    _disposed = true;
    _pending.clear();
    _queuedOrDone.clear();
  }

  void pause() {
    _paused = true;
  }

  void resume() {
    if (_disposed) {
      return;
    }
    _paused = false;
    _pump();
  }

  void schedule(ThreadResourcePrewarmTask task) {
    if (_disposed) {
      return;
    }
    var added = 0;
    final start = task.segmentIndex.clamp(0, task.plan.segments.length - 1);
    final end = (start + task.lookAheadSegments).clamp(
      0,
      task.plan.segments.length - 1,
    );
    for (var index = start; index <= end; index += 1) {
      final segment = task.plan.segments[index];
      for (final request in _requestsForBlocks(task.tid, segment.blocks)) {
        final key = request.cacheKey.trim();
        if (key.isEmpty || !_queuedOrDone.add(key)) {
          continue;
        }
        _pending.add(request);
        added += 1;
        if (added >= task.maxRequests) {
          _pump();
          return;
        }
      }
    }
    _pump();
  }

  Iterable<ImageCacheRequest> _requestsForBlocks(
    String tid,
    List<ThreadPostBodyBlock> blocks,
  ) sync* {
    for (final block in blocks) {
      yield* _requestsForBlock(tid: tid, block: block);
    }
  }

  Iterable<ImageCacheRequest> _requestsForBlock({
    required String tid,
    required ThreadPostBodyBlock block,
  }) sync* {
    if (block is ThreadPostImageBlock) {
      yield ForumImageCacheRequests.threadInline(
        tid: tid,
        url: block.url,
        imageIndex: block.index,
      );
      return;
    }
    if (block is ThreadPostTextBlock) {
      for (final run in block.runs) {
        final image = run.inlineImage;
        if (image != null) {
          yield ForumImageCacheRequests.remoteSmiley(url: image.url);
        }
      }
      return;
    }
    if (block is ThreadPostQuoteBlock) {
      yield* _requestsForBlocks(tid, block.blocks);
    }
  }

  void _pump() {
    if (_disposed || _paused) {
      return;
    }
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final request = _pending.removeAt(0);
      _running += 1;
      unawaited(
        _imageCacheService.ensureCached(request).whenComplete(() {
          _running -= 1;
          _pump();
        }),
      );
    }
  }
}
