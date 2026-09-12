import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_cache.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

void main() {
  late io.Directory root;
  late LibraryCoverThumbnailCache cache;
  const asset = LibraryCoverAssetRef(
    assetId: 'comic/test/source',
    revision: 1,
    kind: LibraryCoverAssetKind.source,
  );
  LibraryCoverThumbnailKey key({int revision = 1, int width = 32}) =>
      LibraryCoverThumbnailKey(
        asset: asset.copyWith(revision: revision),
        width: width,
        height: 48,
      );
  final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('cover-thumbnails-test-');
    cache = LibraryCoverThumbnailCache(rootPath: () async => root.path);
  });
  tearDown(() async {
    await cache.dispose();
    await root.delete(recursive: true);
  });
  Future<void> write(LibraryCoverThumbnailKey target) =>
      cache.write(key: target, ticket: cache.ticket(target), bytes: bytes);

  test(
    'deterministic exact keys survive restart; access writes are deferred',
    () async {
      await write(key());
      final first = await cache.lookup(key());
      expect(first, isNotNull);
      expect(await cache.lookup(key(revision: 2)), isNull);
      expect(await cache.lookup(key(width: 33)), isNull);
      await cache.dispose();
      cache = LibraryCoverThumbnailCache(rootPath: () async => root.path);
      expect((await cache.lookup(key()))?.path, first!.path);
      expect(await first.readAsBytes(), bytes);
      expect((await cache.loadUsage()).budgetedBytes, bytes.length);
    },
  );

  test('clear invalidates tickets captured before encoding', () async {
    final ticket = cache.ticket(key());
    await write(key());
    final cleared = await cache.clearRegular();
    expect(cleared.deletedBytes, bytes.length);
    await cache.write(key: key(), ticket: ticket, bytes: bytes);
    expect(await cache.lookup(key()), isNull);
    await write(key());
    expect(await cache.lookup(key()), isNotNull);
  });

  test(
    'new revision rejects old late writers and keeps the current one',
    () async {
      final old = cache.ticket(key());
      final current = cache.ticket(key(revision: 2));
      await write(key());
      await write(key(revision: 2));
      await cache.invalidateAsset(asset.assetId, retainRevision: 2);
      expect(old.isValid, isFalse);
      expect(current.isValid, isTrue);
      await cache.write(key: key(), ticket: old, bytes: bytes);
      expect(await cache.lookup(key()), isNull);
      expect(await cache.lookup(key(revision: 2)), isNotNull);
    },
  );

  test(
    'budget participant evicts only derived files and rejects foreign keys',
    () async {
      await write(key());
      await io.File(
        '${root.path}/unrelated',
      ).writeAsString('protected fixture');
      final coordinator = CacheBudgetCoordinator(
        participants: <CacheBudgetParticipant>[cache],
      );
      expect((await coordinator.loadReport()).clearableBytes, bytes.length);
      await coordinator.pruneToLimit(maxBytes: 0);
      expect(await cache.lookup(key()), isNull);
      expect(await io.File('${root.path}/unrelated').exists(), isTrue);
      expect(
        await cache.deleteCandidate(
          CacheEvictionCandidate(
            participantId: cache.participantId,
            cacheKey: '../unrelated',
            bytes: 1,
            lastAccessedAt: DateTime(2026),
            priority: CacheEvictionPriority.regularImage,
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'unavailable derivative directory is a miss and write is best effort',
    () async {
      await cache.dispose();
      cache = LibraryCoverThumbnailCache(
        rootPath: () async => throw const io.FileSystemException('fixture'),
      );
      expect(await cache.lookup(key()), isNull);
      await write(key());
    },
  );

  test(
    'original store deletion purges derivatives but ordinary cache clear preserves originals',
    () async {
      final originals = await io.Directory.systemTemp.createTemp(
        'cover-original-test-',
      );
      addTearDown(() => originals.delete(recursive: true));
      final store = LocalLibraryCoverStore(
        rootPath: Future.value(originals.path),
        downloader: _NoDownload(),
        thumbnails: cache,
      );
      final original = await store.fileFor(asset);
      await original.parent.create(recursive: true);
      await original.writeAsBytes(bytes);
      await write(key());
      await cache.clearRegular();
      expect(await original.exists(), isTrue);
      await write(key());
      final ticket = cache.ticket(key());
      await store.deleteAsset(asset.assetId);
      expect(await original.exists(), isFalse);
      expect(await cache.lookup(key()), isNull);
      expect(ticket.isValid, isFalse);
    },
  );
}

class _NoDownload implements LibraryCoverDownloader {
  @override
  Future<void> download({required String url, required String targetPath}) =>
      throw StateError('Network is forbidden');
}
