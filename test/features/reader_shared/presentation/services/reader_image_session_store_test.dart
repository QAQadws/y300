import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/services/default_forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_preload_coordinator.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';
import 'package:y300/features/reader_shared/presentation/widgets/reader_session_image.dart';

void main() {
  test('session entry upgrades from disk ready to decoded', () {
    final store = ReaderImageSessionStore();
    addTearDown(store.dispose);
    final item = _item();
    store.startSession(
      readerOwnerId: item.ownerId,
      generation: 4,
      items: [item],
    );
    final binding = store.bindingFor(item);
    final changes = <ReaderImageSessionStatus>[];
    binding.addListener(() => changes.add(binding.value.status));

    expect(
      store.applyPreloadResult(
        readerOwnerId: item.ownerId,
        itemId: item.id,
        generation: 4,
        sourceUrl: item.url,
        cacheKey: item.cacheKey,
        kind: ReaderImageSessionPreloadKind.disk,
        result: const ForumImagePrecacheResult(
          success: true,
          cacheKey: 'reader-cache-0',
          localPath: 'C:/cache/page.jpg',
        ),
      ),
      isTrue,
    );
    expect(binding.value.status, ReaderImageSessionStatus.diskReady);
    expect(binding.value.localPath, 'C:/cache/page.jpg');

    store.applyPreloadResult(
      readerOwnerId: item.ownerId,
      itemId: item.id,
      generation: 4,
      sourceUrl: item.url,
      cacheKey: item.cacheKey,
      kind: ReaderImageSessionPreloadKind.decoded,
      result: const ForumImagePrecacheResult(
        success: true,
        decoded: true,
        cacheKey: 'reader-cache-0',
        localPath: 'C:/cache/page.jpg',
      ),
    );

    expect(binding.value.status, ReaderImageSessionStatus.decoded);
    expect(binding.value.decoded, isTrue);
    expect(changes, <ReaderImageSessionStatus>[
      ReaderImageSessionStatus.diskReady,
      ReaderImageSessionStatus.decoded,
    ]);
  });

  test('stale generation cannot promote a new owner entry', () {
    final store = ReaderImageSessionStore();
    addTearDown(store.dispose);
    final item = _item();
    store.startSession(
      readerOwnerId: item.ownerId,
      generation: 1,
      items: [item],
    );
    store.startSession(
      readerOwnerId: 'new-owner',
      generation: 2,
      items: [item.copyWith(ownerId: 'new-owner', id: 'new-item')],
    );

    final applied = store.applyPreloadResult(
      readerOwnerId: item.ownerId,
      itemId: item.id,
      generation: 1,
      sourceUrl: item.url,
      cacheKey: item.cacheKey,
      kind: ReaderImageSessionPreloadKind.disk,
      result: const ForumImagePrecacheResult(
        success: true,
        cacheKey: 'reader-cache-0',
        localPath: 'C:/old/page.jpg',
      ),
    );

    expect(applied, isFalse);
    expect(store.generation, 2);
    expect(store.readerOwnerId, 'new-owner');
  });

  test('display and decoded preload use the same local provider key', () {
    final display = resolveDownscaledFileImageProvider(
      localPath: 'C:/cache/page.jpg',
      fit: BoxFit.contain,
      displaySize: const Size(320, 640),
      devicePixelRatio: 1,
    );
    final precache = defaultForumPrecacheImageProviderBuilder(
      localPath: 'C:/cache/page.jpg',
      fit: BoxFit.contain,
      expectedDisplaySize: const Size(320, 640),
      devicePixelRatio: 1,
    );

    expect(display, equals(precache));
  });

  testWidgets('ReaderSessionImage consumes a promoted local path', (
    tester,
  ) async {
    final directory = io.Directory.systemTemp.createTempSync(
      'reader-session-image-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final localFile = io.File('${directory.path}/page.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64));
    final store = ReaderImageSessionStore();
    addTearDown(store.dispose);
    final item = _item();
    store.startSession(
      readerOwnerId: item.ownerId,
      generation: 1,
      items: [item],
    );
    final binding = store.bindingFor(item);
    binding.promoteLocalPath(localFile.path);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderSessionImage(
          sessionBinding: binding,
          cacheRequest: ImageCacheRequest(
            cacheKey: item.cacheKey,
            sourceUrl: item.url,
            ownerType: ImageCacheOwnerType.thread,
            ownerId: item.ownerId,
            role: ImageCacheRole.threadInline,
          ),
          fit: BoxFit.contain,
          expectedDisplaySize: const Size(320, 640),
          placeholder: const SizedBox(key: Key('session-placeholder')),
        ),
      ),
    );
    await tester.pump();

    final cachedImage = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage),
    );
    expect(cachedImage.showDelayedLoadingIndicator, isTrue);
    expect(
      cachedImage.loadingIndicatorDelay,
      const Duration(milliseconds: 300),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<ResizeImage>());
  });
}

ContinuousImageItem _item({String ownerId = 'reader-owner'}) {
  return ContinuousImageItem(
    ownerId: ownerId,
    id: '$ownerId:item-0',
    url: 'https://img.test/page-0.jpg',
    cacheKey: 'reader-cache-0',
    index: 0,
    sourceKind: ContinuousImageSourceKind.threadImageReader,
  );
}

const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
