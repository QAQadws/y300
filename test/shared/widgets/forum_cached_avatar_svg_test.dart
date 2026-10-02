import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_aware_resize_image.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';
import 'package:y300/shared/widgets/forum_cached_avatar.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

import '../../test_support/localized_test_app.dart';

const _avatarUrl =
    'https://bbs.yamibo.com/uc_server/avatar.php?uid=42&size=middle';
const _svg =
    '\uFEFF<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!-- redirected forum default -->\n'
    '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">'
    '<rect width="32" height="32" fill="#885588"/></svg>';

void main() {
  testWidgets(
    'an existing SVG with a jpg filename uses the local default without decoding',
    (tester) async {
      final file = await _temporaryFile(
        tester,
        'avatar.jpg',
        utf8.encode(_svg),
      );
      final cache = _AvatarCache(cached: _localResult(file));
      final network = _NoNetworkCache();
      await _show(tester, cache, network);
      await _waitFor(tester, () => _hasDefaultFrame(tester));

      expect(cache.lookups, hasLength(1));
      expect(cache.downloads, isEmpty);
      expect(cache.decodeFailures, isEmpty);
      expect(network.reads, 0);
      expect(_providers(tester).whereType<FileImage>(), isEmpty);
      expect(
        tester.getSize(find.byType(ForumCachedAvatar)),
        const Size.square(40),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached SVG keeps the neutral surface policy without decoder errors',
    (tester) async {
      final file = await _temporaryFile(
        tester,
        'avatar.jpg',
        utf8.encode(_svg),
      );
      final cache = _AvatarCache(cached: _localResult(file));
      final network = _NoNetworkCache();
      await _show(
        tester,
        cache,
        network,
        policy: ForumAvatarFallbackPolicy.neutralSurface,
      );
      await _waitFor(
        tester,
        () => find.byType(LibraryCachedImage).evaluate().isEmpty,
      );

      expect(find.byKey(const Key('forum-avatar-placeholder')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(cache.lookups, hasLength(1));
      expect(cache.downloads, isEmpty);
      expect(cache.decodeFailures, isEmpty);
      expect(network.reads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a fresh SVG download is checked before any remote or local image display',
    (tester) async {
      final file = await _temporaryFile(
        tester,
        'download.jpg',
        utf8.encode(_svg),
      );
      final cache = _AvatarCache();
      final network = _NoNetworkCache();
      await _show(tester, cache, network);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(cache.downloads, hasLength(1));
      expect(cache.downloads.single.sourceUrl, _avatarUrl);
      expect(find.byType(Image), findsNothing);
      expect(network.reads, 0);

      cache.download.complete(_localResult(file, fromCache: false));
      await _waitFor(tester, () => _hasDefaultFrame(tester));
      expect(cache.lookups, hasLength(1));
      expect(cache.downloads, hasLength(1));
      expect(cache.decodeFailures, isEmpty);
      expect(network.reads, 0);
      expect(_providers(tester).whereType<FileImage>(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a real PNG continues to decode and display its cached file', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() async {
      final image = await createTestImage(width: 5, height: 7, cache: false);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final file = await _temporaryFile(tester, 'avatar.jpg', bytes!);
    final cache = _AvatarCache(cached: _localResult(file));
    final network = _NoNetworkCache();
    await _show(tester, cache, network);
    await _waitFor(
      tester,
      () =>
          _providers(tester).whereType<FileImage>().isNotEmpty &&
          _hasFrame(tester),
    );

    expect(
      _providers(tester).whereType<FileImage>().single.file.path,
      file.path,
    );
    expect(_providers(tester).whereType<AssetImage>(), isEmpty);
    expect(cache.downloads, isEmpty);
    expect(cache.decodeFailures, isEmpty);
    expect(network.reads, 0);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in {
    'HTML containing an SVG': utf8.encode(
      '<html><body><svg xmlns="http://www.w3.org/2000/svg"></svg></body></html>',
    ),
    'corrupt PNG': <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      ...utf8.encode('<svg>not a valid image</svg>'),
    ],
  }.entries) {
    testWidgets('${invalid.key} retains the normal decode failure diagnostic', (
      tester,
    ) async {
      final file = await _temporaryFile(tester, 'avatar.jpg', invalid.value);
      final cache = _AvatarCache(cached: _localResult(file));
      final network = _NoNetworkCache();
      await _show(tester, cache, network);
      await _waitFor(
        tester,
        () => cache.decodeFailures.isNotEmpty && _hasDefaultFrame(tester),
      );

      expect(cache.decodeFailures, hasLength(1));
      expect(cache.decodeFailures.single.ownerId, '42');
      expect(cache.decodeFailures.single.role, ImageCacheRole.avatar);
      expect(cache.decodeErrors.single, isNotNull);
      expect(cache.downloads, isEmpty);
      expect(network.reads, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _show(
  WidgetTester tester,
  _AvatarCache cache,
  _NoNetworkCache network, {
  ForumAvatarFallbackPolicy policy =
      ForumAvatarFallbackPolicy.localDefaultAvatar,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(cache),
        appImageCacheManagerProvider.overrideWith(
          (ref) async => CacheManagerAppImageCacheManager(network),
        ),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
      child: LocalizedTestApp(
        home: Scaffold(
          body: ForumCachedAvatar(
            imageUrl: _avatarUrl,
            ownerId: '42',
            ownerType: ImageCacheOwnerType.profile,
            size: 40,
            fallbackPolicy: policy,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<File> _temporaryFile(
  WidgetTester tester,
  String name,
  List<int> bytes,
) async {
  final file = await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp(
      'forum-avatar-svg-',
    );
    return File('${directory.path}/$name').writeAsBytes(bytes);
  });
  addTearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(() => file!.parent.delete(recursive: true));
  });
  return file!;
}

CachedImageResult _localResult(File file, {bool fromCache = true}) =>
    CachedImageResult(
      success: true,
      localPath: file.path,
      fromCache: fromCache,
    );

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    // Both the bounded file probe and the real image codec run outside the
    // widget test clock. Pump after yielding real IO to commit their results.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) {
      await tester.pump(ForumCachedAvatar.fadeInDuration);
      return;
    }
  }
  fail('Avatar file handling did not settle');
}

bool _hasFrame(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image != null);

bool _hasDefaultFrame(WidgetTester tester) =>
    _providers(tester).whereType<AssetImage>().any(
      (provider) => provider.assetName == forumDefaultAvatarAsset,
    ) &&
    _hasFrame(tester);

Iterable<ImageProvider> _providers(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((image) => _unwrap(image.image));

ImageProvider _unwrap(ImageProvider provider) => switch (provider) {
  ResizeImage() => _unwrap(provider.imageProvider),
  CoverAwareResizeImage() => _unwrap(provider.imageProvider),
  _ => provider,
};

class _AvatarCache extends Fake
    implements ImageCacheService, ImageCacheDecodeFailureReporter {
  _AvatarCache({this.cached});

  final CachedImageResult? cached;
  final lookups = <String>[];
  final downloads = <ImageCacheRequest>[];
  final download = Completer<CachedImageResult>();
  final decodeFailures = <ImageCacheRequest>[];
  final decodeErrors = <Object>[];

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    lookups.add(cacheKey);
    return cached;
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    downloads.add(request);
    return download.future;
  }

  @override
  void reportDecodeFailure({
    required ImageCacheRequest request,
    required Object error,
    StackTrace? stackTrace,
  }) {
    decodeFailures.add(request);
    decodeErrors.add(error);
  }
}

class _NoNetworkCache extends Fake implements BaseCacheManager {
  int reads = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    reads++;
    throw StateError('Avatar display must not bypass the cache write');
  }
}
