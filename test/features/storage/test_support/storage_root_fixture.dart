import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

final class StorageRootFixture {
  StorageRootFixture._({
    required this.workspace,
    required this.sourceRoot,
    required this.targetRoot,
  });

  static const workId = 'fixture-comic';
  static const workTitle = 'Fixture Comic';
  static const episodeId = 'fixture-episode';
  static const cbzFileName = '001-Fixture Episode.cbz';

  final io.Directory workspace;
  final io.Directory sourceRoot;
  final io.Directory targetRoot;

  String get comicDirectoryPath =>
      p.join(sourceRoot.path, 'comics', '$workTitle-${_shortHash(workId)}');

  String get relativeComicDirectory =>
      p.join('comics', '$workTitle-${_shortHash(workId)}');

  static Future<StorageRootFixture> create() async {
    final workspace = await io.Directory.systemTemp.createTemp(
      'y300-storage-migration-fixture-',
    );
    final fixture = StorageRootFixture._(
      workspace: workspace,
      sourceRoot: io.Directory(p.join(workspace.path, 'source')),
      targetRoot: io.Directory(p.join(workspace.path, 'target')),
    );
    await fixture.sourceRoot.create(recursive: true);
    await fixture.targetRoot.create(recursive: true);
    return fixture;
  }

  Future<void> dispose() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  }

  Future<void> populateMixedSource({bool includeTransientFiles = true}) async {
    final comicDirectory = io.Directory(comicDirectoryPath);
    final archiveInput = io.Directory(p.join(workspace.path, 'archive-input'));
    await comicDirectory.create(recursive: true);
    await archiveInput.create(recursive: true);
    await io.File(
      p.join(archiveInput.path, '001.png'),
    ).writeAsBytes(_minimalPngBytes, flush: true);
    await ZipFileEncoder().zipDirectory(
      archiveInput,
      filename: p.join(comicDirectory.path, cbzFileName),
    );
    await io.File(
      p.join(comicDirectory.path, 'cover.jpg'),
    ).writeAsBytes(<int>[0xff, 0xd8, 0xff, 0xd9], flush: true);
    await io.File(p.join(comicDirectory.path, 'meta.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'contentType': 'comic',
        'workId': workId,
        'title': workTitle,
        'chapters': <Object?>[
          <String, Object?>{
            'episodeId': episodeId,
            'cbzFile': cbzFileName,
            'imageFiles': <String>['001.png'],
          },
        ],
      })}\n',
      encoding: utf8,
      flush: true,
    );

    final novelDirectory = io.Directory(
      p.join(sourceRoot.path, 'novels', 'fixture-novel'),
    );
    await novelDirectory.create(recursive: true);
    await io.File(
      p.join(novelDirectory.path, 'chapter-001.txt'),
    ).writeAsString('fixture novel content', encoding: utf8, flush: true);
    await io.File(p.join(sourceRoot.path, 'favorites.json')).writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'remoteCount': 1,
        'syncedAt': '2000-01-01T00:00:00.000Z',
        'threads': <Object?>[
          <String, Object?>{'tid': '10001'},
        ],
      }),
      encoding: utf8,
      flush: true,
    );
    await io.File(p.join(sourceRoot.path, '.nomedia')).writeAsString('');
    await io.File(
      p.join(sourceRoot.path, 'comics', '.nomedia'),
    ).writeAsString('');

    if (includeTransientFiles) {
      await io.File(
        p.join(comicDirectory.path, 'interrupted.cbz.part'),
      ).writeAsString('partial');
      final temporaryDirectory = io.Directory(
        p.join(comicDirectory.path, '.tmp'),
      );
      await temporaryDirectory.create(recursive: true);
      await io.File(
        p.join(temporaryDirectory.path, '001.png'),
      ).writeAsString('temporary');
      await io.File(
        p.join(sourceRoot.path, 'favorites.json.tmp-123'),
      ).writeAsString('temporary');
    }
  }

  Future<void> copyManagedSourceToTarget() async {
    for (final name in const <String>['comics', 'novels']) {
      final source = io.Directory(p.join(sourceRoot.path, name));
      if (await source.exists()) {
        await _copyDirectory(
          source,
          io.Directory(p.join(targetRoot.path, name)),
        );
      }
    }
    final favorites = io.File(p.join(sourceRoot.path, 'favorites.json'));
    if (await favorites.exists()) {
      await favorites.copy(p.join(targetRoot.path, 'favorites.json'));
    }
  }

  Future<void> writeUnknownTopLevelEntity() {
    return io.File(
      p.join(sourceRoot.path, 'unrelated-user-file.txt'),
    ).writeAsString('must not migrate');
  }

  Future<void> writeTargetConflict() async {
    final target = io.File(
      p.join(targetRoot.path, relativeComicDirectory, 'meta.json'),
    );
    await target.parent.create(recursive: true);
    await target.writeAsString('different target content');
  }

  Future<bool> targetContains(String relativePath) {
    return io.File(p.join(targetRoot.path, relativePath)).exists();
  }

  Future<bool> sourceContains(String relativePath) {
    return io.File(p.join(sourceRoot.path, relativePath)).exists();
  }

  static Future<void> _copyDirectory(
    io.Directory source,
    io.Directory target,
  ) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is io.Directory) {
        await _copyDirectory(entity, io.Directory(destination));
      } else if (entity is io.File) {
        await entity.copy(destination);
      }
    }
  }

  static String _shortHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }
}

const List<int> _minimalPngBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
