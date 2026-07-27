import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/services/default_forum_image_precache_service.dart';

void main() {
  test(
    'ensureDiskCached resolves cache request and delegates to service',
    () async {
      final cacheService = _RecordingImageCacheService(
        ensureResult: const CachedImageResult(
          success: true,
          cacheKey: 'thread-inline-page',
          localPath: 'C:/cache/page.jpg',
          fromCache: true,
        ),
      );
      final service = DefaultForumImagePrecacheService(
        imageCacheService: cacheService,
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      );

      final result = await service.ensureDiskCached(_threadSpec());

      expect(result.success, isTrue);
      expect(result.fromDiskCache, isTrue);
      expect(result.localPath, 'C:/cache/page.jpg');
      expect(
        cacheService.ensureRequests.single.role,
        ImageCacheRole.threadInline,
      );
    },
  );

  testWidgets('precacheDecoded does not decode when disk cache fails', (
    tester,
  ) async {
    var decodeCalls = 0;
    final service = DefaultForumImagePrecacheService(
      imageCacheService: _RecordingImageCacheService(
        ensureResult: CachedImageResult.failed,
      ),
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      precacheInvoker: (_, _) async {
        decodeCalls += 1;
      },
      imageProviderBuilder:
          ({
            required localPath,
            required fit,
            required expectedDisplaySize,
            required devicePixelRatio,
          }) => _FakeImageProvider(localPath),
    );

    final result = await _pumpAndPrecache(tester, service, _threadSpec());

    expect(result.success, isFalse);
    expect(result.decoded, isFalse);
    expect(decodeCalls, 0);
  });

  testWidgets('precacheDecoded uses the cached local file provider', (
    tester,
  ) async {
    final builtProviders = <String>[];
    final decodedProviders = <ImageProvider>[];
    final service = DefaultForumImagePrecacheService(
      imageCacheService: _RecordingImageCacheService(
        ensureResult: const CachedImageResult(
          success: true,
          cacheKey: 'thread-inline-page',
          localPath: 'C:/cache/page.jpg',
          fromCache: true,
        ),
      ),
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      precacheInvoker: (provider, _) async {
        decodedProviders.add(provider);
      },
      imageProviderBuilder:
          ({
            required localPath,
            required fit,
            required expectedDisplaySize,
            required devicePixelRatio,
          }) {
            builtProviders.add(localPath);
            return _FakeImageProvider(localPath);
          },
    );

    final result = await _pumpAndPrecache(tester, service, _threadSpec());

    expect(result.success, isTrue);
    expect(result.decoded, isTrue);
    expect(builtProviders, <String>['C:/cache/page.jpg']);
    expect(decodedProviders.single, isA<_FakeImageProvider>());
  });

  testWidgets('precacheDecoded deduplicates repeated specs', (tester) async {
    final completer = Completer<CachedImageResult>();
    final cacheService = _RecordingImageCacheService(
      ensureCompleter: completer,
    );
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cacheService,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      precacheInvoker: (_, _) async {},
      imageProviderBuilder:
          ({
            required localPath,
            required fit,
            required expectedDisplaySize,
            required devicePixelRatio,
          }) => _FakeImageProvider(localPath),
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            unawaited(
              service.precacheDecoded(context: context, spec: _threadSpec()),
            );
            unawaited(
              service.precacheDecoded(context: context, spec: _threadSpec()),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    expect(cacheService.ensureRequests, hasLength(1));
    completer.complete(
      const CachedImageResult(
        success: true,
        cacheKey: 'thread-inline-page',
        localPath: 'C:/cache/page.jpg',
      ),
    );
    await tester.pump();
  });

  testWidgets('remote smiley does not enter decoded preheat', (tester) async {
    final cacheService = _RecordingImageCacheService();
    var decodeCalls = 0;
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cacheService,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      precacheInvoker: (_, _) async {
        decodeCalls += 1;
      },
    );

    final result = await _pumpAndPrecache(
      tester,
      service,
      ForumImageLoadSpec(
        kind: ForumImageKind.remoteSmiley,
        url: Uri.parse('https://bbs.yamibo.com/static/image/smiley/a.gif'),
      ),
    );

    expect(result.success, isFalse);
    expect(decodeCalls, 0);
    expect(cacheService.ensureRequests, isEmpty);
  });
}

Future<ForumImagePrecacheResult> _pumpAndPrecache(
  WidgetTester tester,
  ForumImagePrecacheService service,
  ForumImageLoadSpec spec,
) async {
  late Future<ForumImagePrecacheResult> future;
  await tester.pumpWidget(
    LocalizedTestApp(
      home: Builder(
        builder: (context) {
          future = service.precacheDecoded(
            context: context,
            spec: spec,
            expectedDisplaySize: const Size(320, double.nan),
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return future;
}

ForumImageLoadSpec _threadSpec() {
  return ForumImageLoadSpec(
    kind: ForumImageKind.threadInline,
    url: Uri.parse('https://bbs.yamibo.com/data/attachment/forum/page.jpg'),
    ownerId: '573279',
    imageIndex: 0,
  );
}

class _RecordingImageCacheService implements ImageCacheService {
  _RecordingImageCacheService({
    this.ensureResult = const CachedImageResult(
      success: true,
      cacheKey: 'thread-inline-page',
      localPath: 'C:/cache/page.jpg',
    ),
    this.ensureCompleter,
  });

  final CachedImageResult ensureResult;
  final Completer<CachedImageResult>? ensureCompleter;
  final ensureRequests = <ImageCacheRequest>[];

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    ensureRequests.add(request);
    final completer = ensureCompleter;
    if (completer != null) {
      return completer.future;
    }
    return Future<CachedImageResult>.value(ensureResult);
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

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }
}

class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  const _FakeImageProvider(this.id);

  final String id;

  @override
  Future<_FakeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_FakeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FakeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    throw UnimplementedError();
  }
}
