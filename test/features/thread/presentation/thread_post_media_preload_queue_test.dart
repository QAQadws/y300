import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';
import 'package:y300/features/thread/presentation/thread_post_media_preload_queue.dart';

void main() {
  test(
    'prewarms current render plan segments with concurrency limit',
    () async {
      final service = _ControlledImageCacheService();
      final queue = ThreadPostMediaPreloadQueue(
        imageCacheService: service,
        maxConcurrent: 1,
      );
      const planner = ThreadPostBodyRenderPlanner(maxSegmentTextLength: 20);
      final plan = planner.plan(
        '<p>表情 <img src="static/image/smiley/comcom/2.gif" /></p>'
        '<img file="data/attachment/forum/page-1.jpg" />'
        '<img file="data/attachment/forum/page-2.jpg" />'
        '<img file="data/attachment/forum/page-3.jpg" />',
      );

      queue.schedule(
        ThreadResourcePrewarmTask(
          tid: '100',
          plan: plan,
          segmentIndex: 0,
          lookAheadSegments: 1,
          maxRequests: 2,
        ),
      );

      expect(service.activeRequests, 1);
      expect(service.maxObservedConcurrency, 1);
      expect(service.startedRequests, hasLength(1));

      service.completeNext();
      await Future<void>.delayed(Duration.zero);

      expect(service.startedRequests, hasLength(2));
      expect(
        service.startedRequests.any(
          (request) => request.role == ImageCacheRole.remoteSmiley,
        ),
        isTrue,
      );
      expect(
        service.startedRequests.any(
          (request) => request.sourceUrl.contains('page-1.jpg'),
        ),
        isTrue,
      );
      expect(
        service.startedRequests.any(
          (request) => request.sourceUrl.contains('page-2.jpg'),
        ),
        isFalse,
      );

      queue.dispose();
    },
  );

  test('deduplicates and can pause prewarm requests', () async {
    final service = _ControlledImageCacheService();
    final queue = ThreadPostMediaPreloadQueue(
      imageCacheService: service,
      maxConcurrent: 1,
    );
    const planner = ThreadPostBodyRenderPlanner();
    final plan = planner.plan(
      '<img file="data/attachment/forum/page-1.jpg" />'
      '<img file="data/attachment/forum/page-1.jpg" />',
    );

    queue.pause();
    queue.schedule(
      ThreadResourcePrewarmTask(tid: '100', plan: plan, segmentIndex: 0),
    );

    expect(service.startedRequests, isEmpty);

    queue.resume();
    expect(service.startedRequests, hasLength(1));

    queue.schedule(
      ThreadResourcePrewarmTask(tid: '100', plan: plan, segmentIndex: 0),
    );
    expect(service.startedRequests, hasLength(1));

    queue.dispose();
  });
}

class _ControlledImageCacheService implements ImageCacheService {
  final startedRequests = <ImageCacheRequest>[];
  final _pending = <Completer<CachedImageResult>>[];
  var activeRequests = 0;
  var maxObservedConcurrency = 0;

  void completeNext() {
    final completer = _pending.removeAt(0);
    activeRequests -= 1;
    completer.complete(CachedImageResult.failed);
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    startedRequests.add(request);
    activeRequests += 1;
    if (activeRequests > maxObservedConcurrency) {
      maxObservedConcurrency = activeRequests;
    }
    final completer = Completer<CachedImageResult>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}
