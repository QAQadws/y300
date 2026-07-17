import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test(
    'prepareRoot creates active download storage files only',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'y300-storage-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final service = DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      );

      final root = await service.prepareRoot();

      expect(await io.File(p.join(root.path, '.nomedia')).exists(), isTrue);
      expect(
        await io.File(p.join(root.comicsPath, '.nomedia')).exists(),
        isTrue,
      );
      expect(await io.Directory(root.novelsPath).exists(), isFalse);
      expect(await io.File(root.favoritesJsonPath).exists(), isTrue);
      final favorites = jsonDecode(
        await io.File(root.favoritesJsonPath).readAsString(),
      );
      expect(favorites['schemaVersion'], 1);
    },
  );

  test(
    'safeFileName removes unsafe characters and appends hash for long names',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'y300-storage-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final service = DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      );

      expect(service.safeFileName(' A/B:C*D?"E<>|. '), 'A B C D E');

      final long = service.safeFileName('${'long' * 60}/bad');
      expect(long.length, lessThanOrEqualTo(80));
      expect(long, contains('-'));
    },
  );

  test(
    'deleteComicDownloads removes all directories with the same work hash suffix',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'y300-storage-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final service = DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      );

      final first = await service.prepareComicDirectory(
        workId: 'comic:100',
        title: 'old-title',
      );
      final second = await service.prepareComicDirectory(
        workId: 'comic:100',
        title: 'new-title',
      );
      final other = await service.prepareComicDirectory(
        workId: 'comic:200',
        title: 'other-comic',
      );

      final deleted = await service.deleteComicDownloads(workId: 'comic:100');

      expect(deleted, isTrue);
      expect(await first.exists(), isFalse);
      expect(await second.exists(), isFalse);
      expect(await other.exists(), isTrue);
    },
  );

  test(
    'deleteNovelDownloads removes matching directories and returns false when absent',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'y300-storage-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final service = DefaultDownloadStorageService(
        locationRepository: _FakeStorageLocationRepository(temp.path),
      );

      final root = await service.prepareRoot();
      final novels = io.Directory(root.novelsPath);
      await novels.create(recursive: true);
      final target = io.Directory(
        p.join(novels.path, 'old-novel-${_shortHash('novel:49:100')}'),
      );
      final other = io.Directory(
        p.join(novels.path, 'other-novel-${_shortHash('novel:49:200')}'),
      );
      await target.create();
      await other.create();

      final deleted = await service.deleteNovelDownloads(
        novelId: 'novel:49:100',
      );
      final missing = await service.deleteNovelDownloads(
        novelId: 'novel:49:404',
      );

      expect(deleted, isTrue);
      expect(await target.exists(), isFalse);
      expect(await other.exists(), isTrue);
      expect(missing, isFalse);
    },
  );
}

String _shortHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
}

class _FakeStorageLocationRepository implements StorageLocationRepository {
  _FakeStorageLocationRepository(this.path);

  final String path;

  @override
  Future<String?> getCustomStorageRoot() async => path;

  @override
  Future<String> getDefaultStorageRoot() async => path;

  @override
  Future<String?> pickDirectory() async => path;

  @override
  Future<void> setCustomStorageRoot(String? path) async {}
}
