import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';

import '../test_support/font_test_fixtures.dart';

void main() {
  const validator = FontFileValidator();

  group('FontFileValidator', () {
    test(
      'uses stable content identity and stores the detected font format',
      () {
        final bytes = loadTestFont();
        final first = validator.validate(fileName: 'book.ttf', bytes: bytes);
        final renamed = validator.validate(
          fileName: 'renamed.otf',
          bytes: bytes,
        );

        expect(
          first.id,
          '5f84938e3913d536705e82732c28deb21b9968cd51bc64290df48143c8b1b1fe',
        );
        expect(renamed.id, first.id);
        expect(first.storageFileName, '${first.id}.ttf');
        expect(renamed.storageFileName, first.storageFileName);
        expect(first.byteLength, bytes.length);
        expect(first.displayName, 'book');
        expect(renamed.displayName, 'renamed');
      },
    );

    test('different valid font bytes keep equal file names isolated', () {
      final first = validator.validate(
        fileName: 'book.ttf',
        bytes: loadTestFont(),
      );
      final second = validator.validate(
        fileName: 'book.ttf',
        bytes: loadTestFont(variant: 2),
      );

      expect(second.id, isNot(first.id));
      expect(second.storageFileName, isNot(first.storageFileName));
    });

    test(
      'accepts real CFF OpenType bytes and detects their storage format',
      () {
        final bytes = loadTestCffFont();
        final font = validator.validate(fileName: 'book.otf', bytes: bytes);

        expect(font.storageFileName, '${font.id}.otf');
        expect(font.byteLength, bytes.length);
      },
    );

    test('strips cross-platform paths and control characters from names', () {
      final font = validator.validate(
        fileName: 'C:\\downloads/\u0000My\nFont.TTF ',
        bytes: loadTestFont(),
      );

      expect(font.displayName, 'MyFont');
      expect(font.storageFileName, isNot(contains('downloads')));
    });

    test('bounds display names without splitting surrogate pairs', () {
      final font = validator.validate(
        fileName: '${'a' * 255}😀.ttf',
        bytes: loadTestFont(),
      );

      expect(font.displayName, 'a' * 255);
      expect(font.displayName.length, lessThanOrEqualTo(256));
    });

    test('keeps an extension-only user file name as its display name', () {
      final font = validator.validate(fileName: '.ttf', bytes: loadTestFont());

      expect(font.displayName, '.ttf');
    });

    for (final name in ['font.woff', 'font.woff2', 'font.ttc', 'font', '']) {
      test('rejects unsupported extension $name', () {
        expect(
          () => validator.validate(fileName: name, bytes: loadTestFont()),
          _failsWith(FontLibraryFailure.unsupportedFormat),
        );
      });
    }

    for (final signature in [0x74746366, 0x774f4646, 0x774f4632]) {
      test('rejects a collection or web font disguised as TTF: $signature', () {
        final bytes = loadTestFont();
        ByteData.sublistView(bytes).setUint32(0, signature);

        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.unsupportedFormat),
        );
      });
    }

    test('rejects empty and truncated files', () {
      for (final bytes in [
        Uint8List(0),
        Uint8List(11),
        // The final two bytes are alignment padding, not declared table data.
        Uint8List.sublistView(loadTestFont(), 0, 1025),
      ]) {
        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      }
    });

    test('accepts omitted padding after the final declared table', () {
      final font = validator.validate(
        fileName: 'font.ttf',
        bytes: Uint8List.sublistView(loadTestFont(), 0, 1026),
      );

      expect(font.byteLength, 1026);
    });

    test('rejects oversized bytes before parsing the font', () {
      expect(
        () => validator.validate(
          fileName: 'font.ttf',
          bytes: Uint8List(FontFileValidator.maxFontBytes + 1),
        ),
        _failsWith(FontLibraryFailure.tooLarge),
      );
    });

    test('rejects duplicate, overlapping, and out-of-bounds table records', () {
      final duplicate = loadTestFont();
      duplicate.setRange(28, 32, duplicate.sublist(12, 16));
      final overlap = loadTestFont();
      ByteData.sublistView(overlap).setUint32(20, 333);
      final outside = loadTestFont();
      ByteData.sublistView(outside).setUint32(20, 0xffffffff);

      for (final bytes in [duplicate, overlap, outside]) {
        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      }
    });

    for (final tag in [
      'head',
      'maxp',
      'cmap',
      'name',
      'hhea',
      'hmtx',
      'OS/2',
      'post',
      'glyf',
      'loca',
    ]) {
      test('rejects a missing required $tag table', () {
        final bytes = loadTestFont();
        final record = _recordOffset(bytes, tag);
        bytes.setRange(record, record + 4, 'xxxx'.codeUnits);

        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      });
    }

    test('rejects invalid font magic and unusable metrics', () {
      final badMagic = loadTestFont();
      ByteData.sublistView(badMagic)
          .setUint32(_tableOffset(badMagic, 'head') + 12, 0);
      final badUnits = loadTestFont();
      ByteData.sublistView(badUnits)
          .setUint16(_tableOffset(badUnits, 'head') + 18, 0);
      final badMetrics = loadTestFont();
      ByteData.sublistView(badMetrics)
          .setUint16(_tableOffset(badMetrics, 'hhea') + 34, 0xffff);
      for (final bytes in [badMagic, badUnits, badMetrics]) {
        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      }
    });

    test('rejects invalid or out-of-bounds TrueType glyph locations', () {
      final badFormat = loadTestFont();
      ByteData.sublistView(badFormat)
          .setInt16(_tableOffset(badFormat, 'head') + 50, 2);
      final badLocation = loadTestFont();
      ByteData.sublistView(badLocation)
          .setUint16(_tableOffset(badLocation, 'loca') + 4, 0xffff);
      final decreasing = loadTestFont();
      ByteData.sublistView(decreasing)
          .setUint16(_tableOffset(decreasing, 'loca'), 10);
      for (final bytes in [badFormat, badLocation, decreasing]) {
        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      }
    });

    test(
      'rejects cmap offsets escaping their table into other valid bytes',
      () {
        final bytes = loadTestFont();
        ByteData.sublistView(bytes)
            .setUint32(_tableOffset(bytes, 'cmap') + 8, 60);

        expect(
          () => validator.validate(fileName: 'font.ttf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      },
    );

    test('rejects name strings escaping their table', () {
      final bytes = loadTestFont();
      ByteData.sublistView(bytes)
          .setUint16(_tableOffset(bytes, 'name') + 6 + 10, 0xffff);

      expect(
        () => validator.validate(fileName: 'font.ttf', bytes: bytes),
        _failsWith(FontLibraryFailure.invalidFont),
      );
    });

    test('rejects malformed CFF headers within otherwise valid SFNT bytes', () {
      final badVersion = loadTestCffFont();
      badVersion[_tableOffset(badVersion, 'CFF ')] = 0;
      final badHeaderSize = loadTestCffFont();
      badHeaderSize[_tableOffset(badHeaderSize, 'CFF ') + 2] = 0;

      for (final bytes in [badVersion, badHeaderSize]) {
        expect(
          () => validator.validate(fileName: 'font.otf', bytes: bytes),
          _failsWith(FontLibraryFailure.invalidFont),
        );
      }
    });
  });
}

Matcher _failsWith(FontLibraryFailure code) => throwsA(
  isA<FontLibraryException>().having((error) => error.code, 'code', code),
);

int _recordOffset(Uint8List bytes, String tag) {
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < data.getUint16(4); index++) {
    final offset = 12 + index * 16;
    if (String.fromCharCodes(bytes.sublist(offset, offset + 4)) == tag) {
      return offset;
    }
  }
  throw ArgumentError.value(tag, 'tag');
}

int _tableOffset(Uint8List bytes, String tag) =>
    ByteData.sublistView(bytes).getUint32(_recordOffset(bytes, tag) + 8);
