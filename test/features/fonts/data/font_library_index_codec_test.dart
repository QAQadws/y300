import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/data/services/font_library_index_codec.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';

void main() {
  const codec = FontLibraryIndexCodec();
  final id = 'a' * 64;
  final font = ImportedFont(
    id: id,
    displayName: '阅读字体',
    storageFileName: '$id.ttf',
    byteLength: 1024,
  );

  test('round trips a versioned relative-path-only index', () {
    final encoded = codec.encode(<ImportedFont>[font]);
    expect(codec.decode(encoded), <ImportedFont>[font]);
    expect(jsonDecode(encoded), <String, Object>{
      'version': 1,
      'fonts': <Map<String, Object>>[
        <String, Object>{
          'id': id,
          'displayName': '阅读字体',
          'storageFileName': '$id.ttf',
          'byteLength': 1024,
        },
      ],
    });
  });

  test('rejects malformed roots and missing schema fields', () {
    for (final source in <String>[
      'broken',
      '[]',
      'null',
      '{}',
      '{"version":0,"fonts":[]}',
      '{"version":1}',
      '{"version":1,"fonts":{}}',
      '{"version":1,"fonts":[null]}',
    ]) {
      expect(() => codec.decode(source), _throwsCorrupt, reason: source);
    }
  });

  test('distinguishes an unsupported future schema from corrupt data', () {
    expect(
      () => codec.decode('{"version":2,"fonts":[]}'),
      throwsA(
        isA<FontLibraryException>().having(
          (error) => error.code,
          'code',
          FontLibraryFailure.unsupportedLibraryVersion,
        ),
      ),
    );
  });

  test(
    'rejects unsafe paths and metadata that cannot be trusted on restart',
    () {
      final valid = <String, Object?>{
        'id': id,
        'displayName': '阅读字体',
        'storageFileName': '$id.ttf',
        'byteLength': 1024,
      };
      for (final changed in <Map<String, Object?>>[
        <String, Object?>{...valid, 'id': '../outside'},
        <String, Object?>{...valid, 'id': 'A' * 64},
        <String, Object?>{...valid, 'displayName': ''},
        <String, Object?>{...valid, 'displayName': ' '},
        <String, Object?>{...valid, 'displayName': 'x' * 257},
        <String, Object?>{...valid, 'storageFileName': '../outside.ttf'},
        <String, Object?>{...valid, 'storageFileName': '$id.ttf/../outside'},
        <String, Object?>{...valid, 'storageFileName': 'C:\\outside.ttf'},
        <String, Object?>{...valid, 'storageFileName': '${'b' * 64}.ttf'},
        <String, Object?>{...valid, 'byteLength': 0},
        <String, Object?>{...valid, 'byteLength': 64 * 1024 * 1024 + 1},
        <String, Object?>{...valid, 'byteLength': '1024'},
      ]) {
        expect(
          () => codec.decode(
            jsonEncode(<String, Object>{
              'version': 1,
              'fonts': <Map<String, Object?>>[changed],
            }),
          ),
          _throwsCorrupt,
          reason: '$changed',
        );
      }
    },
  );

  test('rejects duplicate content identities instead of losing one entry', () {
    final entry = <String, Object>{
      'id': id,
      'displayName': font.displayName,
      'storageFileName': font.storageFileName,
      'byteLength': font.byteLength,
    };
    expect(
      () => codec.decode(
        jsonEncode(<String, Object>{
          'version': 1,
          'fonts': <Map<String, Object>>[entry, entry],
        }),
      ),
      _throwsCorrupt,
    );
  });

  test('returns an immutable metadata snapshot', () {
    final result = codec.decode(codec.encode(<ImportedFont>[font]));
    expect(() => result.clear(), throwsUnsupportedError);
  });
}

final _throwsCorrupt = throwsA(
  isA<FontLibraryException>().having(
    (error) => error.code,
    'code',
    FontLibraryFailure.corruptLibrary,
  ),
);
