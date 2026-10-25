import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:y300/features/fonts/data/services/font_library_index_codec.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';

typedef FontLibraryDirectoryProvider = Future<Directory> Function();

/// A single instance owns mutations to an application-private font directory.
final class FileFontLibraryRepository implements FontLibraryRepository {
  FileFontLibraryRepository({
    required FontLibraryDirectoryProvider directoryProvider,
    FontFileValidator validator = const FontFileValidator(),
  }) : _directoryProvider = directoryProvider,
       _validator = validator;

  static const indexFileName = 'index.json';
  static const _temporaryIndexFileName = '$indexFileName.tmp';
  static const _backupIndexFileName = '$indexFileName.bak';
  static final _fontIdPattern = RegExp(r'^[0-9a-f]{64}$');

  final FontLibraryDirectoryProvider _directoryProvider;
  final FontFileValidator _validator;
  final _codec = const FontLibraryIndexCodec();
  final _changes = StreamController<void>.broadcast(sync: true);
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _disposed = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ImportedFont>> listFonts() => _enqueue(() async {
    final directory = await _directory();
    return _readIndex(directory);
  });

  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (bytes.length > FontFileValidator.maxFontBytes) {
      return Future<ImportedFont>.error(
        const FontLibraryException(FontLibraryFailure.tooLarge),
      );
    }
    // Callers may reuse picker buffers before the serialized write starts.
    final snapshot = Uint8List.fromList(bytes);
    return _enqueue(() async {
      final candidate = await _validate(fileName, snapshot, _validator);
      final directory = await _directory();
      final fonts = await _readIndex(directory);
      final existing = _find(fonts, candidate.id);
      final imported = existing == null
          ? candidate
          : ImportedFont(
              id: candidate.id,
              displayName: existing.displayName,
              storageFileName: candidate.storageFileName,
              byteLength: candidate.byteLength,
            );
      if (existing != null) {
        try {
          await _readVerified(directory, existing);
          return existing;
        } on FontLibraryException catch (error) {
          if (error.code != FontLibraryFailure.notFound &&
              error.code != FontLibraryFailure.invalidFont) {
            rethrow;
          }
        }
      }

      final destination = _fontFile(directory, imported);
      final destinationWasPresent = await destination.exists();
      await _writeFont(destination, snapshot);
      if (existing == null || imported != existing) {
        try {
          await _writeIndex(directory, <ImportedFont>[
            for (final font in fonts)
              if (font.id != imported.id) font,
            imported,
          ]);
        } catch (_) {
          if (!destinationWasPresent) {
            await _deleteBestEffort(destination);
          }
          rethrow;
        }
        if (existing != null &&
            existing.storageFileName != imported.storageFileName) {
          await _deleteBestEffort(_fontFile(directory, existing));
        }
      }
      _changes.add(null);
      return imported;
    });
  }

  @override
  Future<Uint8List> readFont(String fontId) => _enqueue(() async {
    _requireId(fontId);
    final directory = await _directory();
    final font = _find(await _readIndex(directory), fontId);
    if (font == null) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    return _readVerified(directory, font);
  });

  @override
  Future<void> deleteFont(String fontId) => _enqueue(() async {
    _requireId(fontId);
    final directory = await _directory();
    final fonts = await _readIndex(directory);
    final font = _find(fonts, fontId);
    if (font == null) {
      return;
    }
    await _writeIndex(directory, <ImportedFont>[
      for (final item in fonts)
        if (item.id != fontId) item,
    ]);
    // The index is the commit point. A failed unlink leaves only an orphan,
    // never a live entry pointing at a missing file after restart.
    await _deleteBestEffort(_fontFile(directory, font));
    _changes.add(null);
  });

  @override
  Future<void> dispose() {
    if (_disposal != null) {
      return _disposal!;
    }
    _disposed = true;
    return _disposal = _tail.then((_) => _changes.close());
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_disposed) {
      return Future<T>.error(
        const FontLibraryException(FontLibraryFailure.storage),
      );
    }
    final operation = _tail.then((_) async {
      try {
        return await action();
      } on FileSystemException {
        throw const FontLibraryException(FontLibraryFailure.storage);
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<Directory> _directory() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<ImportedFont>> _readIndex(Directory directory) async {
    final index = File(p.join(directory.path, indexFileName));
    final backup = File(p.join(directory.path, _backupIndexFileName));
    final indexType = await FileSystemEntity.type(
      index.path,
      followLinks: false,
    );
    if (indexType == FileSystemEntityType.file) {
      return _decodeIndex(index);
    }
    if (indexType != FileSystemEntityType.notFound) {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    final backupType = await FileSystemEntity.type(
      backup.path,
      followLinks: false,
    );
    if (backupType == FileSystemEntityType.file) {
      final fonts = await _decodeIndex(backup);
      // A crash may occur after parking the old index, before publication.
      // Only that previous committed index may be recovered; never the temp.
      await backup.rename(index.path);
      return fonts;
    }
    if (backupType != FileSystemEntityType.notFound) {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    return const <ImportedFont>[];
  }

  Future<List<ImportedFont>> _decodeIndex(File file) async {
    try {
      final bytes = await _readBounded(
        file,
        maxBytes: FontLibraryIndexCodec.maxIndexBytes,
        wrongSize: FontLibraryFailure.corruptLibrary,
      );
      return _codec.decode(utf8.decode(bytes));
    } on FormatException {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
  }

  Future<void> _writeIndex(
    Directory directory,
    List<ImportedFont> fonts,
  ) async {
    final source = _codec.encode(fonts);
    final index = File(p.join(directory.path, indexFileName));
    final temporary = File(p.join(directory.path, _temporaryIndexFileName));
    final backup = File(p.join(directory.path, _backupIndexFileName));
    var parkedPrevious = false;
    try {
      await _writeFlushed(temporary, utf8.encode(source));
      await _deleteRegularFile(backup);
      if (await index.exists()) {
        await index.rename(backup.path);
        parkedPrevious = true;
      }
      await temporary.rename(index.path);
    } catch (_) {
      if (parkedPrevious && !await index.exists()) {
        try {
          await backup.rename(index.path);
        } on FileSystemException {
          // Keep the backup for the next _readIndex recovery attempt.
        }
      }
      await _deleteBestEffort(temporary);
      rethrow;
    }
    await _deleteBestEffort(backup);
  }

  Future<void> _writeFont(File destination, Uint8List bytes) async {
    final temporary = File('${destination.path}.tmp');
    try {
      await _writeFlushed(temporary, bytes);
      await temporary.rename(destination.path);
    } catch (_) {
      await _deleteBestEffort(temporary);
      rethrow;
    }
  }

  Future<Uint8List> _readVerified(
    Directory directory,
    ImportedFont font,
  ) async {
    final file = _fontFile(directory, font);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
    if (type != FileSystemEntityType.file) {
      throw const FontLibraryException(FontLibraryFailure.invalidFont);
    }
    final bytes = await _readBounded(
      file,
      maxBytes: FontFileValidator.maxFontBytes,
      expectedLength: font.byteLength,
      wrongSize: FontLibraryFailure.invalidFont,
    );
    final ImportedFont validated;
    try {
      validated = await _validate(font.storageFileName, bytes, _validator);
    } on FontLibraryException {
      // A committed entry already declares a supported container. A different
      // signature on disk is corruption, not a new unsupported user import.
      throw const FontLibraryException(FontLibraryFailure.invalidFont);
    }
    if (validated.id != font.id ||
        validated.byteLength != font.byteLength ||
        validated.storageFileName != font.storageFileName) {
      throw const FontLibraryException(FontLibraryFailure.invalidFont);
    }
    return bytes;
  }

  static Future<Uint8List> _readBounded(
    File file, {
    required int maxBytes,
    required FontLibraryFailure wrongSize,
    int? expectedLength,
  }) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length > maxBytes ||
          (expectedLength != null && length != expectedLength)) {
        throw FontLibraryException(wrongSize);
      }
      final bytes = Uint8List(length);
      var offset = 0;
      while (offset < bytes.length) {
        final read = await handle.readInto(bytes, offset);
        if (read == 0) {
          throw FontLibraryException(wrongSize);
        }
        offset += read;
      }
      if (await handle.readByte() != -1) {
        throw FontLibraryException(wrongSize);
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  static Future<ImportedFont> _validate(
    String fileName,
    Uint8List bytes,
    FontFileValidator validator,
  ) => Isolate.run(() => validator.validate(fileName: fileName, bytes: bytes));

  static Future<void> _writeFlushed(File file, List<int> bytes) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw const FileSystemException('Expected a private regular file.');
    }
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  static Future<void> _deleteRegularFile(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('Expected a private regular file.');
    }
    await file.delete();
  }

  static Future<void> _deleteBestEffort(File file) async {
    try {
      await _deleteRegularFile(file);
    } on FileSystemException {
      // Cleanup is retryable and must not turn a committed change into failure.
    }
  }

  static File _fontFile(Directory directory, ImportedFont font) =>
      File(p.join(directory.path, font.storageFileName));

  static ImportedFont? _find(List<ImportedFont> fonts, String id) {
    for (final font in fonts) {
      if (font.id == id) {
        return font;
      }
    }
    return null;
  }

  static void _requireId(String id) {
    if (!_fontIdPattern.hasMatch(id)) {
      throw const FontLibraryException(FontLibraryFailure.notFound);
    }
  }
}
