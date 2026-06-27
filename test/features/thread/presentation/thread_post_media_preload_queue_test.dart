import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/presentation/thread_post_media_preload_queue.dart';

void main() {
  test(
    'preloads nearby post images and smileys with concurrency limit',
    () async {
      final service = _ControlledImageCacheService();
      final queue = ThreadPostMediaPreloadQueue(
        imageCacheService: service,
        maxConcurrent: 2,
      );

      queue.preloadNearbyPosts(
        tid: '100',
        posts: <ThreadPost>[
          _post('p1', '<p>无图</p>'),
          _post(
            'p2',
            '<img file="data/attachment/forum/page-1.jpg" />'
                '<p>表情 <img src="static/image/smiley/comcom/2.gif" /></p>',
          ),
          _post(
            'p3',
            '<img file="data/attachment/forum/page-1.jpg" />'
                '<img file="data/attachment/forum/page-2.jpg" />',
          ),
          _post(
            'p4',
            '<p>范围外 <img file="data/attachment/forum/page-3.jpg" /></p>',
          ),
        ],
        centerIndex: 1,
        radius: 1,
      );

      expect(service.activeRequests, 2);
      expect(service.maxObservedConcurrency, 2);
      expect(service.startedCacheKeys, hasLength(2));

      service.completeNext();
      await Future<void>.delayed(Duration.zero);

      expect(service.startedCacheKeys, hasLength(3));
      expect(
        service.startedCacheKeys.toSet(),
        hasLength(3),
        reason: '重复的 page-1 图片只应预加载一次',
      );
      expect(
        service.startedRequests.any(
          (request) => request.role == ImageCacheRole.remoteSmiley,
        ),
        isTrue,
      );
      expect(
        service.startedRequests.any((request) {
          return request.sourceUrl.contains('page-3.jpg');
        }),
        isFalse,
      );

      queue.dispose();
    },
  );
}

ThreadPost _post(String pid, String message) {
  return ThreadPost(
    pid: pid,
    author: 'alice',
    authorId: '1',
    message: message,
    number: 1,
    isFirst: false,
    dateline: 'today',
  );
}

class _ControlledImageCacheService implements ImageCacheService {
  final startedRequests = <ImageCacheRequest>[];
  final _pending = <Completer<CachedImageResult>>[];
  var activeRequests = 0;
  var maxObservedConcurrency = 0;

  List<String> get startedCacheKeys {
    return startedRequests.map((request) => request.cacheKey).toList();
  }

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
