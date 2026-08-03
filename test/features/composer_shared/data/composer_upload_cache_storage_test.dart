import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';

void main() {
  test(
    'retains an atomic composer-owned copy without touching the source',
    () async {
      final fileSystem = MemoryFileSystem.test(style: FileSystemStyle.posix);
      final source = fileSystem.file('/gallery/photo.JPG')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final storage = LocalComposerUploadCacheStorage(
        fileSystem: fileSystem,
        cacheRootPath: () async => '/cache/reply_uploads',
      );

      final retained = await storage.retainUploadedCopy(
        sourcePath: source.path,
        localId: '../unsafe id',
        fileName: '../photo.JPG',
      );

      expect(source.existsSync(), isTrue);
      expect(source.readAsBytesSync(), <int>[1, 2, 3]);
      expect(retained, startsWith('/cache/reply_uploads/'));
      expect(retained, endsWith('/preview.jpg'));
      expect(fileSystem.file(retained).readAsBytesSync(), <int>[1, 2, 3]);
      expect(storage.cachePathExists(retained), isTrue);
    },
  );

  test('deletes only files inside the composer-owned cache root', () async {
    final fileSystem = MemoryFileSystem.test(style: FileSystemStyle.posix);
    final owned = fileSystem.file('/cache/reply_uploads/a/preview.jpg')
      ..createSync(recursive: true);
    final gallery = fileSystem.file('/gallery/photo.jpg')
      ..createSync(recursive: true);
    final storage = LocalComposerUploadCacheStorage(
      fileSystem: fileSystem,
      cacheRootPath: () async => '/cache/reply_uploads',
    );

    expect(await storage.deleteCachePathIfOwned(gallery.path), isFalse);
    expect(gallery.existsSync(), isTrue);
    expect(await storage.deleteCachePathIfOwned(owned.path), isTrue);
    expect(owned.existsSync(), isFalse);
  });
}
