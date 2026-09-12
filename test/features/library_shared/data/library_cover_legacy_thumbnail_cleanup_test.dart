import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/library_shared/data/services/library_cover_legacy_thumbnail_cleanup.dart';

void main() {
  test('upgrade cleanup batches only recognized old thumbnail files', () async {
    final root = await io.Directory.systemTemp.createTemp(
      'old-cover-thumbnails-',
    );
    final cleanup = LibraryCoverLegacyThumbnailCleanup(
      rootPath: () async => root.path,
      batchSize: 1,
    );
    addTearDown(() async {
      cleanup.dispose();
      await root.delete(recursive: true);
    });
    final asset = io.Directory(p.join(root.path, 'a' * 64));
    await asset.create();
    final names = [
      'r1-32x48.png',
      'r1-64x96.png.1.part',
      'user.png',
      'r1-32x48.png.unknown.part',
    ];
    for (final name in names) {
      await io.File(p.join(asset.path, name)).writeAsBytes([1]);
    }
    final unknown = io.Directory(p.join(root.path, 'unrelated'));
    await unknown.create();
    await io.File(p.join(unknown.path, names.first)).writeAsBytes([1]);
    await cleanup.run();
    expect(await io.File(p.join(asset.path, names[0])).exists(), isFalse);
    expect(await io.File(p.join(asset.path, names[1])).exists(), isFalse);
    expect(await io.File(p.join(asset.path, names[2])).exists(), isTrue);
    expect(await io.File(p.join(asset.path, names[3])).exists(), isTrue);
    expect(await io.File(p.join(unknown.path, names.first)).exists(), isTrue);
  });

  test('upgrade cleanup does not create a missing root', () async {
    final root = await io.Directory.systemTemp.createTemp('old-cover-root-');
    addTearDown(() => root.delete(recursive: true));
    final missing = io.Directory(p.join(root.path, 'missing'));
    final cleanup = LibraryCoverLegacyThumbnailCleanup(
      rootPath: () async => missing.path,
    );
    await cleanup.run();
    expect(await missing.exists(), isFalse);
    cleanup.dispose();
  });
}
