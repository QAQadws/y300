import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const source = LibraryCoverAssetRef(
    assetId: 'comic/1/source',
    revision: 4,
    kind: LibraryCoverAssetKind.source,
    sourceUrl: 'https://img.test/cover.jpg',
  );
  final store = _NoopCoverStore();
  final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 3);

  LibraryCoverImageProvider provider({
    LibraryCoverAssetRef asset = source,
    LibraryCoverDecodeTarget target = const LibraryCoverDecodeTarget.thumbnail(
      widthPx: 202,
      heightPx: 303,
    ),
  }) {
    return LibraryCoverImageProvider(
      asset: asset,
      decodeTarget: target,
      store: store,
      scheduler: scheduler,
    );
  }

  test('key ignores local/network source changes', () {
    final remote = provider();
    final local = provider(
      asset: source.copyWith(legacyLocalPath: r'C:\cache\cover.jpg'),
    );

    expect(local.cacheKey, remote.cacheKey);
    expect(local, remote);
  });

  test('revision or exact target invalidates the image cache key', () {
    expect(
      provider(
        target: const LibraryCoverDecodeTarget.thumbnail(
          widthPx: 220,
          heightPx: 330,
        ),
      ).cacheKey,
      isNot(provider().cacheKey),
    );
    expect(
      provider(asset: source.copyWith(revision: 5)).cacheKey,
      isNot(provider().cacheKey),
    );
  });

  test('original request has an isolated non-thumbnail cache key', () {
    final original = provider(
      target: const LibraryCoverDecodeTarget.original(),
    );

    expect(original.cacheKey, isNot(provider().cacheKey));
    expect(original.decodeTarget.isOriginal, isTrue);
    expect(original.cacheKey.targetWidthPx, isNull);
    expect(original.cacheKey.targetHeightPx, isNull);
  });

  test('obtainKey completes synchronously without touching the store', () {
    final future = provider().obtainKey(ImageConfiguration.empty);

    expect(future, isA<SynchronousFuture<LibraryCoverImageKey>>());
    expect(store.callCount, 0);
  });

  test('detail foreground and background resolve to the same provider', () {
    final first = LibraryCoverProviderResolver.resolve(
      asset: source,
      displaySize: const Size(120, 168),
      devicePixelRatio: 2,
      store: store,
      scheduler: scheduler,
    );
    final second = LibraryCoverProviderResolver.resolve(
      asset: source,
      displaySize: const Size(120, 168),
      devicePixelRatio: 2,
      store: store,
      scheduler: scheduler,
    );

    expect(first.cacheKey, second.cacheKey);
    expect(first, second);
    expect(store.callCount, 0);
  });

  test('different physical layout sizes do not share a cache key', () {
    final first = LibraryCoverProviderResolver.resolve(
      asset: source,
      displaySize: const Size(101, 151.5),
      devicePixelRatio: 2,
      store: store,
      scheduler: scheduler,
    );
    final second = LibraryCoverProviderResolver.resolve(
      asset: source,
      displaySize: const Size(110, 165),
      devicePixelRatio: 2,
      store: store,
      scheduler: scheduler,
    );

    expect(first.cacheKey, isNot(second.cacheKey));
    expect(second.decodeTarget.targetWidthPx, 220);
    expect(second.decodeTarget.targetHeightPx, 330);
  });

  testWidgets('provider image has no progressive fallback layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 101,
          height: 151.5,
          child: LibraryCoverProviderImage(
            provider: provider(),
            fit: BoxFit.cover,
            placeholder: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Stack), findsNothing);
  });
}

class _NoopCoverStore implements LibraryCoverStore {
  int callCount = 0;

  @override
  Future<int> calculateUsageBytes() async => 0;

  @override
  Future<void> deleteAsset(String assetId) async {}

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) async {}

  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) async {
    callCount += 1;
    throw UnimplementedError();
  }

  @override
  Future<io.File> fileFor(LibraryCoverAssetRef asset) async {
    callCount += 1;
    throw UnimplementedError();
  }

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) async {}

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {}
}
