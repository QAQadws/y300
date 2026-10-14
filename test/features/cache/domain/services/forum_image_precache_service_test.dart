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
import 'package:y300/core/media/encoded_image_dimension_probe.dart';
import 'package:y300/core/media/image_display_provider.dart';

void main() {
  test('allowRetry forwards only the resolved cache request', () {
    final cache = _RetryableRecordingImageCacheService();
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cache,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
    );
    final spec = _threadSpec();
    final expected = const DefaultForumImageRequestResolver()
        .resolveCacheRequest(spec)!;

    service.allowRetry(spec);
    service.allowRetry(
      ForumImageLoadSpec(
        kind: ForumImageKind.externalInline,
        url: Uri.parse('https://external.test/image.jpg'),
      ),
    );

    expect(cache.retryRequests, hasLength(1));
    final request = cache.retryRequests.single;
    expect(request.cacheKey, expected.cacheKey);
    expect(request.sourceUrl, expected.sourceUrl);
    expect(request.ownerType, expected.ownerType);
    expect(request.ownerId, expected.ownerId);
    expect(request.role, expected.role);
    expect(cache.ensureRequests, isEmpty);
  });

  test('retry allowance retains an in-flight shared disk request', () async {
    final disk = Completer<CachedImageResult>();
    final cache = _RetryableRecordingImageCacheService(ensureCompleter: disk);
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cache,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
    );
    final first = service.ensureDiskCached(_threadSpec());
    service.allowRetry(_threadSpec());
    final second = service.ensureDiskCached(_threadSpec());

    expect(cache.retryRequests, hasLength(1));
    expect(cache.ensureRequests, hasLength(1));
    disk.complete(CachedImageResult.failed);
    expect((await first).success, isFalse);
    expect((await second).success, isFalse);

    await service.ensureDiskCached(_threadSpec());
    expect(cache.ensureRequests, hasLength(2));
  });

  test('allowRetry remains optional for legacy cache services', () async {
    final cache = _RecordingImageCacheService();
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cache,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
    );

    service.allowRetry(_threadSpec());
    expect(cache.ensureRequests, isEmpty);
    expect((await service.ensureDiskCached(_threadSpec())).success, isTrue);
    expect(cache.ensureRequests, hasLength(1));
  });

  for (final intrinsic in [const Size(2000, 1000), const Size(2000, 100000)]) {
    testWidgets('bounded decode admits by encoded dimensions $intrinsic', (
      tester,
    ) async {
      final decodedProviders = <ImageProvider>[];
      final probe = _DimensionProbe(intrinsic);
      final service = DefaultForumImagePrecacheService(
        imageCacheService: _RecordingImageCacheService(),
        imageRequestResolver: const DefaultForumImageRequestResolver(),
        dimensionProbe: probe,
        precacheInvoker: (provider, _) async => decodedProviders.add(provider),
      );
      late BuildContext context;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final result = await service.precacheDecodedScoped(
        context: context,
        spec: _threadSpec(),
        scope: ForumImageWorkToken(),
        expectedDisplaySize: const Size(320, double.nan),
        maxDecodedBytes: 2 * 1024 * 1024,
      );
      expect(result.success, isTrue);
      expect(probe.calls, 1);
      final allowed = intrinsic.height < 100000;
      expect(result.decoded, allowed);
      expect(result.decodePrecacheAttempted, allowed);
      expect(decodedProviders, hasLength(allowed ? 1 : 0));
      if (allowed) {
        final display = resolveDownscaledFileImageProvider(
          localPath: result.localPath!,
          fit: BoxFit.fitWidth,
          displaySize: const Size(320, 160),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        expect(
          await decodedProviders.single.obtainKey(ImageConfiguration.empty),
          await display.obtainKey(ImageConfiguration.empty),
        );
      }
    });
  }

  testWidgets('bounded unknown width never decodes at original size', (
    tester,
  ) async {
    final probe = _DimensionProbe(const Size(400, 200));
    var decoded = 0;
    final service = DefaultForumImagePrecacheService(
      imageCacheService: _RecordingImageCacheService(),
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      dimensionProbe: probe,
      precacheInvoker: (_, _) async => decoded++,
    );
    late BuildContext context;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = await service.precacheDecodedScoped(
      context: context,
      spec: _threadSpec(),
      scope: ForumImageWorkToken(),
      maxDecodedBytes: 1000000,
    );
    expect(result.success, isTrue);
    expect(result.decoded, isFalse);
    expect(decoded, 0);
    expect(probe.calls, 0);
  });

  test('cancelled queued disk work does not download', () async {
    final disk = Completer<CachedImageResult>();
    final cache = _RecordingImageCacheService(ensureCompleter: disk);
    final service = DefaultForumImagePrecacheService(
      imageCacheService: cache,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      maxConcurrentDiskTasks: 1,
    );
    final first = service.ensureDiskCached(_threadSpec());
    final token = ForumImageWorkToken();
    final second = service.ensureDiskCachedScoped(
      ForumImageLoadSpec(
        kind: ForumImageKind.threadInline,
        url: Uri.parse('https://bbs.yamibo.com/second.jpg'),
        ownerId: '573279',
      ),
      scope: token,
    );
    token.cancel();
    disk.complete(const CachedImageResult(success: true, localPath: 'file'));
    await first;
    expect((await second).failureReason, 'cancelled_before_decode');
    expect(cache.ensureRequests, hasLength(1));
  });

  testWidgets('cancelled admission probe skips decode', (tester) async {
    final probe = _DimensionProbe(
      const Size(400, 200),
      pending: Completer<Size>(),
    );
    var decoded = 0;
    final service = DefaultForumImagePrecacheService(
      imageCacheService: _RecordingImageCacheService(),
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      dimensionProbe: probe,
      precacheInvoker: (_, _) async => decoded++,
    );
    late BuildContext context;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final token = ForumImageWorkToken();
    final work = service.precacheDecodedScoped(
      context: context,
      spec: _threadSpec(),
      scope: token,
      expectedDisplaySize: const Size(320, double.nan),
      maxDecodedBytes: 1000000,
    );
    await tester.pump();
    token.cancel();
    probe.pending!.complete(const Size(400, 200));
    expect((await work).failureReason, 'cancelled_before_decode');
    expect(decoded, 0);
  });

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

  testWidgets('cancelled scope skips decode after disk caching finishes', (
    tester,
  ) async {
    final diskCompleter = Completer<CachedImageResult>();
    var decodeCalls = 0;
    final service = DefaultForumImagePrecacheService(
      imageCacheService: _RecordingImageCacheService(
        ensureCompleter: diskCompleter,
      ),
      imageRequestResolver: const DefaultForumImageRequestResolver(),
      precacheInvoker: (_, _) async => decodeCalls += 1,
      imageProviderBuilder:
          ({
            required localPath,
            required fit,
            required expectedDisplaySize,
            required devicePixelRatio,
          }) => _FakeImageProvider(localPath),
    );
    final token = ForumImageWorkToken();
    late Future<ForumImagePrecacheResult> future;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            future = service.precacheDecodedScoped(
              context: context,
              spec: _threadSpec(),
              scope: token,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    token.cancel();
    diskCompleter.complete(
      const CachedImageResult(
        success: true,
        cacheKey: 'thread-inline-page',
        localPath: 'C:/cache/page.jpg',
      ),
    );

    final result = await future;
    expect(result.failureReason, 'cancelled_before_decode');
    expect(decodeCalls, 0);
  });

  testWidgets(
    'cancelling one consumer does not cancel a shared decode still in use',
    (tester) async {
      final decodeCompleter = Completer<void>();
      var decodeCalls = 0;
      final service = DefaultForumImagePrecacheService(
        imageCacheService: _RecordingImageCacheService(),
        imageRequestResolver: const DefaultForumImageRequestResolver(),
        precacheInvoker: (_, _) {
          decodeCalls += 1;
          return decodeCompleter.future;
        },
        imageProviderBuilder:
            ({
              required localPath,
              required fit,
              required expectedDisplaySize,
              required devicePixelRatio,
            }) => _FakeImageProvider(localPath),
      );
      late BuildContext imageContext;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (context) {
              imageContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final firstToken = ForumImageWorkToken();
      final secondToken = ForumImageWorkToken();
      final first = service.precacheDecodedScoped(
        context: imageContext,
        spec: _threadSpec(),
        scope: firstToken,
      );
      await tester.pump();
      final second = service.precacheDecodedScoped(
        context: imageContext,
        spec: _threadSpec(),
        scope: secondToken,
      );
      firstToken.cancel();
      decodeCompleter.complete();

      final firstResult = await first;
      final secondResult = await second;
      expect(firstResult.failureReason, 'cancelled_before_decode');
      expect(secondResult.success, isTrue);
      expect(decodeCalls, 1);
    },
  );

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

class _DimensionProbe implements EncodedImageDimensionProbe {
  _DimensionProbe(this.size, {this.pending});
  final Size size;
  final Completer<Size>? pending;
  int calls = 0;
  @override
  Future<Size> probe({
    required String cacheKey,
    required String localPath,
  }) async {
    calls++;
    return pending == null ? size : pending!.future;
  }
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

class _RetryableRecordingImageCacheService extends _RecordingImageCacheService
    implements ImageCacheFailureControl {
  _RetryableRecordingImageCacheService({super.ensureCompleter});

  final retryRequests = <ImageCacheRequest>[];

  @override
  void allowRetry(ImageCacheRequest request) {
    retryRequests.add(request);
  }
}

class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  const _FakeImageProvider(this.id);

  final String id;
  @override
  bool operator ==(Object other) =>
      other is _FakeImageProvider && other.id == id;
  @override
  int get hashCode => id.hashCode;

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
