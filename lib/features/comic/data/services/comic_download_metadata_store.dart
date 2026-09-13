import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:path/path.dart' as p;

/// Shares each work's read/modify/write boundary between downloads and cover
/// maintenance. Callers hold the storage-root lease for the entire operation.
class ComicDownloadMetadataStore {
  final Map<String, Future<void>> _tails = {};
  int _temporaryId = 0;
  Future<T> run<T>(io.Directory directory, Future<T> Function() action) {
    final key = p.normalize(directory.absolute.path);
    final operation = (_tails[key] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return operation;
  }

  Future<Map<String, Object?>?> read(io.Directory directory) async {
    final file = io.File(p.join(directory.path, 'meta.json'));
    if (!await file.exists()) return null;
    // Malformed metadata must not silently become an empty chapter list.
    final value = jsonDecode(await file.readAsString(encoding: utf8));
    if (value is! Map) throw const FormatException('Invalid download metadata');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> write(io.Directory directory, Map<String, Object?> value) async {
    final target = io.File(p.join(directory.path, 'meta.json'));
    final temporary = io.File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_temporaryId++}.part',
    );
    try {
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(value)}\n',
        encoding: utf8,
        flush: true,
      );
      // Rename replaces the old file atomically. Never delete the old metadata
      // first: a failed publication must leave its chapters readable.
      await temporary.rename(target.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on io.FileSystemException {
        // A cleanup failure after publication must not roll back a valid CBZ.
      }
    }
  }
}
