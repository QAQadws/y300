import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/fonts/data/repositories/file_font_library_repository.dart';
import 'package:y300/features/fonts/data/services/font_library_index_codec.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';

import '../test_support/font_test_fixtures.dart';

void main() {
  late Directory directory;
  late FileFontLibraryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('y300-font-library-');
    repository = FileFontLibraryRepository(
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await directory.delete(recursive: true);
  });

  File indexFile() => File(p.join(directory.path, 'index.json'));
  File storedFile(ImportedFont font) =>
      File(p.join(directory.path, font.storageFileName));

  Future<ImportedFont> import({int variant = 1, String name = 'Reading.ttf'}) =>
      repository.importFont(
        fileName: name,
        bytes: loadTestFont(variant: variant),
      );

  test(
    'starts empty and stores an independent private copy across restart',
    () async {
      expect(await repository.listFonts(), isEmpty);
      final bytes = loadTestFont();
      final original = Uint8List.fromList(bytes);
      final importFuture = repository.importFont(
        fileName: 'Reading.ttf',
        bytes: bytes,
      );
      bytes.fillRange(0, bytes.length, 0);
      final font = await importFuture;

      expect(font.id, sha256.convert(original).toString());
      expect(font.storageFileName, '${font.id}.ttf');
      expect(await storedFile(font).readAsBytes(), original);
      expect(await repository.readFont(font.id), original);

      final restarted = FileFontLibraryRepository(
        directoryProvider: () async => directory,
      );
      addTearDown(restarted.dispose);
      expect(await restarted.listFonts(), <ImportedFont>[font]);
      expect(await restarted.readFont(font.id), original);
      final manifest = await indexFile().readAsString(encoding: utf8);
      expect(manifest, isNot(contains(directory.path)));
    },
  );

  test('deduplicates content and preserves the first display name', () async {
    var mutations = 0;
    final subscription = repository.changes.listen((_) => mutations++);
    addTearDown(subscription.cancel);
    final first = await import(name: 'Original.ttf');
    final repeated = await import(name: 'Renamed.otf');

    expect(repeated, first);
    expect(await repository.listFonts(), <ImportedFont>[first]);
    expect(mutations, 1);
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.ttf'))
          .length,
      1,
    );
  });

  test(
    'serializes overlapping imports and deletion without losing entries',
    () async {
      final firstImport = import();
      final secondImport = import(variant: 2, name: 'Other.ttf');
      final firstId = sha256.convert(loadTestFont()).toString();
      final deletion = repository.deleteFont(firstId);

      final first = await firstImport;
      final second = await secondImport;
      await deletion;

      expect(await repository.listFonts(), <ImportedFont>[second]);
      expect(await storedFile(first).exists(), isFalse);
      expect(await repository.readFont(second.id), loadTestFont(variant: 2));
    },
  );

  test(
    'a rejected import preserves previous metadata and queued operations',
    () async {
      final font = await import();
      final manifest = await indexFile().readAsString(encoding: utf8);

      await expectLater(
        repository.importFont(
          fileName: 'Broken.ttf',
          bytes: Uint8List.sublistView(loadTestFont(), 0, 20),
        ),
        _throwsCode(FontLibraryFailure.invalidFont),
      );

      expect(await indexFile().readAsString(encoding: utf8), manifest);
      expect(await repository.listFonts(), <ImportedFont>[font]);
      final second = await import(variant: 2);
      expect(await repository.listFonts(), <ImportedFont>[font, second]);
    },
  );

  test(
    'failed index publication rolls back a new font and sends no event',
    () async {
      final first = await import();
      final manifest = await indexFile().readAsString(encoding: utf8);
      final blockedTemporary = Directory(
        p.join(directory.path, 'index.json.tmp'),
      );
      await blockedTemporary.create();
      var mutations = 0;
      final subscription = repository.changes.listen((_) => mutations++);
      addTearDown(subscription.cancel);
      final secondId = sha256.convert(loadTestFont(variant: 2)).toString();

      await expectLater(
        import(variant: 2),
        _throwsCode(FontLibraryFailure.storage),
      );

      expect(await repository.listFonts(), <ImportedFont>[first]);
      expect(await indexFile().readAsString(encoding: utf8), manifest);
      expect(
        await File(p.join(directory.path, '$secondId.ttf')).exists(),
        isFalse,
      );
      expect(mutations, 0);

      await blockedTemporary.delete();
      final second = await import(variant: 2);
      expect(await repository.listFonts(), <ImportedFont>[first, second]);
      expect(mutations, 1);
    },
  );

  test(
    'failed first publication does not expose an uncommitted font',
    () async {
      final blockedTemporary = Directory(
        p.join(directory.path, 'index.json.tmp'),
      );
      await blockedTemporary.create();

      await expectLater(import(), _throwsCode(FontLibraryFailure.storage));

      expect(await repository.listFonts(), isEmpty);
      expect(await indexFile().exists(), isFalse);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.endsWith('.ttf'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('failed deletion publication leaves the font usable', () async {
    final font = await import();
    await Directory(p.join(directory.path, 'index.json.tmp')).create();

    await expectLater(
      repository.deleteFont(font.id),
      _throwsCode(FontLibraryFailure.storage),
    );

    expect(await repository.listFonts(), <ImportedFont>[font]);
    expect(await repository.readFont(font.id), loadTestFont());
  });

  test(
    'recovers only the previous committed index after an interrupted swap',
    () async {
      final font = await import();
      final previousManifest = await indexFile().readAsString(encoding: utf8);
      await indexFile().rename(p.join(directory.path, 'index.json.bak'));
      await File(p.join(directory.path, 'index.json.tmp')).writeAsString(
        const FontLibraryIndexCodec().encode(const <ImportedFont>[]),
        encoding: utf8,
        flush: true,
      );

      final restarted = FileFontLibraryRepository(
        directoryProvider: () async => directory,
      );
      addTearDown(restarted.dispose);
      expect(await restarted.listFonts(), <ImportedFont>[font]);
      expect(await indexFile().readAsString(encoding: utf8), previousManifest);
      expect(await restarted.readFont(font.id), loadTestFont());
    },
  );

  test('prefers the newly committed index to an old backup', () async {
    final first = await import();
    final firstManifest = await indexFile().readAsString(encoding: utf8);
    final second = await import(variant: 2);
    await File(p.join(directory.path, 'index.json.bak'))
        .writeAsString(firstManifest, encoding: utf8, flush: true);

    expect(await repository.listFonts(), <ImportedFont>[first, second]);
    await repository.deleteFont(first.id);
    expect(await repository.listFonts(), <ImportedFont>[second]);
  });

  test('never adopts an uncommitted temporary index or orphan font', () async {
    final font = await import();
    await indexFile().rename(p.join(directory.path, 'index.json.tmp'));

    final restarted = FileFontLibraryRepository(
      directoryProvider: () async => directory,
    );
    addTearDown(restarted.dispose);
    expect(await restarted.listFonts(), isEmpty);
    await expectLater(
      restarted.readFont(font.id),
      _throwsCode(FontLibraryFailure.notFound),
    );
    final reimported = await restarted.importFont(
      fileName: 'Reading.ttf',
      bytes: loadTestFont(),
    );
    expect(reimported, font);
    expect(await restarted.listFonts(), <ImportedFont>[font]);
  });

  test(
    'does not overwrite a malformed manifest even with a usable backup',
    () async {
      final font = await import();
      await indexFile().copy(p.join(directory.path, 'index.json.bak'));
      await indexFile().writeAsString('broken', encoding: utf8, flush: true);

      await expectLater(
        repository.listFonts(),
        _throwsCode(FontLibraryFailure.corruptLibrary),
      );
      await expectLater(
        import(variant: 2),
        _throwsCode(FontLibraryFailure.corruptLibrary),
      );
      expect(await indexFile().readAsString(encoding: utf8), 'broken');
      expect(await storedFile(font).exists(), isTrue);
    },
  );

  test('does not overwrite a future manifest version', () async {
    const manifest = '{"version":2,"fonts":[]}';
    await indexFile().writeAsString(manifest, encoding: utf8, flush: true);

    await expectLater(
      import(),
      _throwsCode(FontLibraryFailure.unsupportedLibraryVersion),
    );
    expect(await indexFile().readAsString(encoding: utf8), manifest);
  });

  test('rejects an oversized manifest before decoding it', () async {
    await indexFile().writeAsBytes(
      Uint8List(FontLibraryIndexCodec.maxIndexBytes + 1),
      flush: true,
    );

    await expectLater(
      repository.listFonts(),
      _throwsCode(FontLibraryFailure.corruptLibrary),
    );
  });

  test(
    'keeps missing entries visible for deletion or explicit repair',
    () async {
      final font = await import();
      await storedFile(font).delete();

      expect(await repository.listFonts(), <ImportedFont>[font]);
      await expectLater(
        repository.readFont(font.id),
        _throwsCode(FontLibraryFailure.notFound),
      );

      final repaired = await import(name: 'Replacement.ttf');
      expect(repaired, font);
      expect(await repository.readFont(font.id), loadTestFont());
      await storedFile(font).delete();
      await repository.deleteFont(font.id);
      expect(await repository.listFonts(), isEmpty);
    },
  );

  test(
    'detects changed same-size content and permits explicit repair',
    () async {
      final font = await import();
      final damaged = loadTestFont();
      damaged[damaged.length - 1] ^= 1;
      await storedFile(font).writeAsBytes(damaged, flush: true);

      await expectLater(
        repository.readFont(font.id),
        _throwsCode(FontLibraryFailure.invalidFont),
      );
      expect(await repository.listFonts(), <ImportedFont>[font]);
      final repaired = await import();
      expect(repaired, font);
      expect(await repository.readFont(font.id), loadTestFont());
    },
  );

  test('repairs a known font whose container signature was damaged', () async {
    final font = await import();
    final damaged = loadTestFont()..fillRange(0, 4, 0);
    await storedFile(font).writeAsBytes(damaged, flush: true);

    await expectLater(
      repository.readFont(font.id),
      _throwsCode(FontLibraryFailure.invalidFont),
    );
    expect(await import(), font);
    expect(await repository.readFont(font.id), loadTestFont());
  });

  test('rejects a changed file size before reading its payload', () async {
    final font = await import();
    await storedFile(font)
        .writeAsBytes(<int>[...loadTestFont(), 0], flush: true);

    await expectLater(
      repository.readFont(font.id),
      _throwsCode(FontLibraryFailure.invalidFont),
    );
    expect(await repository.listFonts(), <ImportedFont>[font]);
  });

  test('repairs inconsistent metadata for a known content ID', () async {
    final font = await import();
    await indexFile().writeAsString(
      const FontLibraryIndexCodec().encode(<ImportedFont>[
        ImportedFont(
          id: font.id,
          displayName: font.displayName,
          storageFileName: font.storageFileName,
          byteLength: font.byteLength + 1,
        ),
      ]),
      encoding: utf8,
      flush: true,
    );

    await expectLater(
      repository.readFont(font.id),
      _throwsCode(FontLibraryFailure.invalidFont),
    );
    expect(await import(name: 'Renamed.ttf'), font);
    expect(await repository.listFonts(), <ImportedFont>[font]);
    expect(await repository.readFont(font.id), loadTestFont());
  });

  test(
    'rejects unknown or traversal IDs without accessing another path',
    () async {
      await expectLater(
        repository.readFont('../outside'),
        _throwsCode(FontLibraryFailure.notFound),
      );
      await expectLater(
        repository.deleteFont('../outside'),
        _throwsCode(FontLibraryFailure.notFound),
      );
      await expectLater(
        repository.readFont('0' * 64),
        _throwsCode(FontLibraryFailure.notFound),
      );
      await repository.deleteFont('0' * 64);
      expect(await repository.listFonts(), isEmpty);
    },
  );

  test(
    'deletion never recursively removes a non-file at a managed path',
    () async {
      final font = await import();
      final path = storedFile(font).path;
      await storedFile(font).delete();
      await Directory(path).create();
      final sentinel = File(p.join(path, 'keep.txt'));
      await sentinel.writeAsString('keep', encoding: utf8);

      await repository.deleteFont(font.id);

      expect(await repository.listFonts(), isEmpty);
      expect(await sentinel.readAsString(encoding: utf8), 'keep');
    },
  );

  test(
    'disposal drains accepted writes and rejects subsequent operations',
    () async {
      final ready = Completer<Directory>();
      final delayed = FileFontLibraryRepository(
        directoryProvider: () => ready.future,
      );
      final pending = delayed.importFont(
        fileName: 'Reading.ttf',
        bytes: loadTestFont(),
      );
      final disposed = delayed.dispose();
      ready.complete(directory);
      final imported = await pending;
      await disposed;
      await delayed.dispose();

      expect(await repository.listFonts(), <ImportedFont>[imported]);
      await expectLater(
        delayed.listFonts(),
        _throwsCode(FontLibraryFailure.storage),
      );
    },
  );
}

Matcher _throwsCode(FontLibraryFailure code) => throwsA(
  isA<FontLibraryException>().having((error) => error.code, 'code', code),
);
