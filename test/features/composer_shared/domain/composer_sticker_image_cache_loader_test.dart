import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';

void main() {
  test('returns cached sticker without entering network queue', () async {
    final service = _FakeImageCacheService();
    final request = _request('bugcat/Capoo16.gif');
    service.cached[request.cacheKey] = CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/cache/Capoo16.gif',
      fromCache: true,
    );
    final loader = ComposerStickerImageCacheLoader(
      imageCacheService: service,
      now: () => DateTime.utc(2026),
      delay: (_) async {},
    );

    final result = await loader.ensureCached(request);

    expect(result.localPath, '/cache/Capoo16.gif');
    expect(result.fromCache, isTrue);
    expect(service.ensureCalls, isEmpty);
  });

  test('serializes sticker cache misses with 500ms network gaps', () async {
    final service = _FakeImageCacheService();
    var now = DateTime.utc(2026);
    service.now = () => now;
    final delays = <Duration>[];
    final loader = ComposerStickerImageCacheLoader(
      imageCacheService: service,
      now: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await Future.wait([
      loader.ensureCached(_request('bugcat/1.gif')),
      loader.ensureCached(_request('bugcat/2.gif')),
      loader.ensureCached(_request('bugcat/3.gif')),
    ]);

    expect(service.ensureCalls.map((call) => call.request.cacheKey), [
      _request('bugcat/1.gif').cacheKey,
      _request('bugcat/2.gif').cacheKey,
      _request('bugcat/3.gif').cacheKey,
    ]);
    expect(
      service.ensureCalls.map(
        (call) => call.startedAt.difference(DateTime.utc(2026)),
      ),
      const [
        Duration.zero,
        Duration(milliseconds: 500),
        Duration(milliseconds: 1000),
      ],
    );
    expect(delays, const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 500),
    ]);
  });

  test('reuses in-flight miss for the same sticker cache key', () async {
    final service = _FakeImageCacheService();
    final request = _request('bugcat/Capoo16.gif');
    final loader = ComposerStickerImageCacheLoader(
      imageCacheService: service,
      now: () => DateTime.utc(2026),
      delay: (_) async {},
    );

    final results = await Future.wait([
      loader.ensureCached(request),
      loader.ensureCached(request),
    ]);

    expect(service.ensureCalls, hasLength(1));
    expect(results[0].cacheKey, request.cacheKey);
    expect(results[1].cacheKey, request.cacheKey);
  });
}

ImageCacheRequest _request(String imagePath) {
  return ForumImageCacheRequests.remoteSmiley(
    url: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
  );
}

class _FakeImageCacheService implements ImageCacheService {
  final cached = <String, CachedImageResult>{};
  final ensureCalls = <_EnsureCall>[];
  DateTime Function()? now;

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    return cached[cacheKey];
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    ensureCalls.add(
      _EnsureCall(request: request, startedAt: now?.call() ?? DateTime.now()),
    );
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: '/cache/${request.cacheKey}',
    );
  }

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
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _EnsureCall {
  const _EnsureCall({required this.request, required this.startedAt});

  final ImageCacheRequest request;
  final DateTime startedAt;
}
