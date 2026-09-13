import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

void main() {
  late io.Directory root;
  late LibraryCoverThumbnailStore cache;
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
    cache = LibraryCoverThumbnailStore(rootPath: () async => root.path);
  });
  tearDown(() async {
    await cache.dispose();
    await root.delete(recursive: true);
  });
  Future<bool> write(LibraryCoverThumbnailKey target) {
    cache.registerTarget(target);
    return cache.write(key: target, ticket: cache.ticket(target), bytes: bytes);
  }

  test(
    'deterministic exact keys survive restart; no index is needed',
    () async {
      await write(key());
      final first = await cache.lookup(key());
      expect(first, isNotNull);
      expect(await cache.lookup(key(revision: 2)), isNull);
      expect(await cache.lookup(key(width: 33)), isNull);
      await cache.dispose();
      cache = LibraryCoverThumbnailStore(rootPath: () async => root.path);
      expect((await cache.lookup(key()))?.path, first!.path);
      expect(await first.readAsBytes(), bytes);
      expect(await cache.calculateUsageBytes(), bytes.length);
    },
  );

  test('asset deletion invalidates tickets captured before encoding', () async {
    final ticket = cache.ticket(key());
    await write(key());
    await cache.invalidateAsset(asset.assetId);
    await cache.write(key: key(), ticket: ticket, bytes: bytes);
    expect(await cache.lookup(key()), isNull);
    await write(key());
    expect(await cache.lookup(key()), isNotNull);
  });

  test(
    'new revision rejects old late writers and keeps the current one',
    () async {
      final old = cache.ticket(key());
      await write(key());
      cache.registerTarget(key(revision: 2));
      final current = cache.ticket(key(revision: 2));
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
    'target changes replace only after successful publication and cancel old tickets',
    () async {
      final a = key();
      final b = key(width: 40);
      await write(a);
      final oldFile = (await cache.lookup(a))!;
      cache.registerTarget(b);
      final stale = cache.ticket(b);
      cache.registerTarget(a);
      expect(stale.isValid, isFalse);
      expect(await cache.write(key: b, ticket: stale, bytes: bytes), isFalse);
      expect(await oldFile.exists(), isTrue);
      cache.registerTarget(b);
      expect(
        await cache.write(key: b, ticket: cache.ticket(b), bytes: Uint8List(0)),
        isFalse,
      );
      expect(await oldFile.exists(), isTrue);
      expect(await write(b), isTrue);
      expect(await oldFile.exists(), isFalse);
      expect(await cache.calculateUsageBytes(), bytes.length);
      expect(await write(b), isFalse);
    },
  );

  test(
    'successful maintenance removes crash leftovers but preserves unknown files',
    () async {
      await write(key());
      final file = (await cache.lookup(key()))!;
      final stale = io.File('${file.parent.path}/r1-12x18.png');
      final part = io.File('${file.parent.path}/r1-12x18.png.123-1.part');
      final unknown = io.File('${file.parent.path}/user.png');
      await stale.writeAsBytes(bytes);
      await part.writeAsBytes(bytes);
      await unknown.writeAsBytes(bytes);
      await write(key());
      expect(await stale.exists(), isFalse);
      expect(await part.exists(), isFalse);
      expect(await unknown.exists(), isTrue);
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'unavailable derivative directory is a miss and write is best effort',
    () async {
      await cache.dispose();
      cache = LibraryCoverThumbnailStore(
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
      await CacheBudgetCoordinator(
        participants: <CacheBudgetParticipant>[],
      ).clearRegular();
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
