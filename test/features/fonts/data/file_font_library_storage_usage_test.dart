import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/fonts/data/repositories/file_font_library_repository.dart';
import 'package:y300/features/fonts/data/services/font_library_index_codec.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';

import '../test_support/font_test_fixtures.dart';

void main() {
  late Directory root;
  late Directory fonts;
  late FileFontLibraryRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('y300-font-accounting-');
    fonts = Directory(p.join(root.path, 'fonts'));
    repository = FileFontLibraryRepository(
      directoryProvider: () async => fonts,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await root.delete(recursive: true);
  });

  test(
    'an unused library reports zero without creating its directory',
    () async {
      expect(await repository.calculateUsageBytes(), 0);
      expect(await fonts.exists(), isFalse);
    },
  );

  test(
    'counts physical font, index, temporary, backup and orphan files once',
    () async {
      final bytes = loadTestFont();
      await repository.importFont(fileName: 'Reading.ttf', bytes: bytes);
      final indexLength = await File(p.join(fonts.path, 'index.json')).length();
      await File(p.join(fonts.path, 'orphan.ttf')).writeAsBytes([1, 2, 3]);
      await File(p.join(fonts.path, 'index.json.tmp')).writeAsBytes([4, 5]);
      await File(p.join(fonts.path, 'index.json.bak')).writeAsBytes([6]);
      final nested = await Directory(p.join(fonts.path, 'leftover')).create();
      await File(p.join(nested.path, 'unknown.bin')).writeAsBytes([7, 8, 9, 0]);

      expect(
        await repository.calculateUsageBytes(),
        bytes.length + indexLength + 3 + 2 + 1 + 4,
      );
      expect(await repository.listFonts(), hasLength(1));
    },
  );

  test('counting does not parse, recover or rewrite an index', () async {
    await fonts.create();
    final backup = File(p.join(fonts.path, 'index.json.bak'));
    final temporary = File(p.join(fonts.path, 'index.json.tmp'));
    const backupSource = '{"future":true}';
    const temporarySource = 'uncommitted';
    await backup.writeAsString(backupSource, encoding: utf8);
    await temporary.writeAsString(temporarySource, encoding: utf8);
    var mutations = 0;
    final subscription = repository.changes.listen((_) => mutations++);
    addTearDown(subscription.cancel);

    expect(
      await repository.calculateUsageBytes(),
      utf8.encode(backupSource).length + utf8.encode(temporarySource).length,
    );
    expect(await File(p.join(fonts.path, 'index.json')).exists(), isFalse);
    expect(await backup.readAsString(encoding: utf8), backupSource);
    expect(await temporary.readAsString(encoding: utf8), temporarySource);
    expect(mutations, 0);

    final corrupt = File(p.join(fonts.path, 'index.json'));
    await corrupt.writeAsBytes([0xff]);
    expect(
      await repository.calculateUsageBytes(),
      utf8.encode(backupSource).length +
          utf8.encode(temporarySource).length +
          1,
    );
    expect(await corrupt.readAsBytes(), [0xff]);
    expect(mutations, 0);
  });

  test('queued counts see completed imports and deletions', () async {
    final bytes = loadTestFont();
    final importing = repository.importFont(
      fileName: 'Reading.ttf',
      bytes: bytes,
    );
    final afterImport = repository.calculateUsageBytes();
    final imported = await importing;
    final indexSource = const FontLibraryIndexCodec().encode([imported]);
    expect(await afterImport, bytes.length + utf8.encode(indexSource).length);

    final deleting = repository.deleteFont(imported.id);
    final afterDelete = repository.calculateUsageBytes();
    await deleting;
    expect(
      await afterDelete,
      utf8
          .encode(const FontLibraryIndexCodec().encode(<ImportedFont>[]))
          .length,
    );
  });

  test(
    'directory I/O failures remain typed failures instead of zero',
    () async {
      final failed = FileFontLibraryRepository(
        directoryProvider: () => Future<Directory>.error(
          const FileSystemException('private directory unavailable'),
        ),
      );
      addTearDown(failed.dispose);
      await expectLater(
        failed.calculateUsageBytes(),
        _throwsCode(FontLibraryFailure.storage),
      );
      expect(await fonts.exists(), isFalse);
    },
  );

  test('a regular file in place of the root is a storage failure', () async {
    await File(fonts.path).writeAsBytes([1]);
    await expectLater(
      repository.calculateUsageBytes(),
      _throwsCode(FontLibraryFailure.storage),
    );
    expect(await File(fonts.path).readAsBytes(), [1]);
  });

  test('disposal drains an accepted count and rejects later counts', () async {
    final ready = Completer<Directory>();
    final delayed = FileFontLibraryRepository(
      directoryProvider: () => ready.future,
    );
    final counting = delayed.calculateUsageBytes();
    final disposed = delayed.dispose();
    ready.complete(fonts);
    expect(await counting, 0);
    await disposed;
    await expectLater(
      delayed.calculateUsageBytes(),
      _throwsCode(FontLibraryFailure.storage),
    );
  });

  test('links to external files or directories are not counted', () async {
    await fonts.create();
    final outside = await Directory(p.join(root.path, 'outside')).create();
    final outsideFile = File(p.join(outside.path, 'font.ttf'));
    await outsideFile.writeAsBytes(List<int>.filled(100, 1));
    try {
      await Link(p.join(fonts.path, 'font.ttf')).create(outsideFile.path);
      await Link(p.join(fonts.path, 'nested')).create(outside.path);
    } on FileSystemException catch (error) {
      if (Platform.isWindows && error.osError?.errorCode == 1314) {
        markTestSkipped('Windows symbolic-link privilege is unavailable.');
        return;
      }
      rethrow;
    }
    await File(p.join(fonts.path, 'index.json')).writeAsBytes([1, 2]);

    expect(await repository.calculateUsageBytes(), 2);
    expect(await outsideFile.length(), 100);
  });
}

Matcher _throwsCode(FontLibraryFailure code) => throwsA(
  isA<FontLibraryException>().having((error) => error.code, 'code', code),
);
