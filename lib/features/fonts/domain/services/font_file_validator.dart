import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/font_library_failure.dart';
import '../models/imported_font.dart';

/// Bounded SFNT validation before bytes reach the platform font parser.
///
/// Flutter may finish loading a rejected font without throwing. These checks
/// reject broken containers and core tables; they do not interpret glyph
/// instructions or guarantee that every platform accepts every outline.
final class FontFileValidator {
  const FontFileValidator();

  static const int maxFontBytes = 64 * 1024 * 1024;

  ImportedFont validate({required String fileName, required Uint8List bytes}) {
    if (bytes.length > maxFontBytes) {
      throw const FontLibraryException(FontLibraryFailure.tooLarge);
    }
    final baseName = fileName.replaceAll('\\', '/').split('/').last.trim();
    final extensionAt = baseName.lastIndexOf('.');
    final extension = extensionAt < 0
        ? ''
        : baseName.substring(extensionAt).toLowerCase();
    if (extension != '.ttf' && extension != '.otf') {
      throw const FontLibraryException(FontLibraryFailure.unsupportedFormat);
    }
    if (bytes.length < 12) {
      _invalid();
    }
    final data = ByteData.sublistView(bytes);
    final version = data.getUint32(0);
    if (version != 0x00010000 && version != 0x4f54544f) {
      throw const FontLibraryException(FontLibraryFailure.unsupportedFormat);
    }
    final tableCount = data.getUint16(4);
    final directoryEnd = 12 + tableCount * 16;
    if (tableCount == 0 || directoryEnd > bytes.length) {
      _invalid();
    }
    final tables = <String, _FontTable>{};
    for (var index = 0; index < tableCount; index++) {
      final record = 12 + index * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      final offset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (tables.containsKey(tag) ||
          offset < directoryEnd ||
          offset > bytes.length ||
          length > bytes.length - offset) {
        _invalid();
      }
      tables[tag] = _FontTable(offset, length);
    }
    final ranges = tables.values.where((table) => table.length > 0).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    for (var index = 1; index < ranges.length; index++) {
      if (ranges[index].offset <
          ranges[index - 1].offset + ranges[index - 1].length) {
        _invalid();
      }
    }

    _FontTable require(String tag, int minimumLength) {
      final table = tables[tag];
      if (table == null || table.length < minimumLength) {
        _invalid();
      }
      return table;
    }

    final head = require('head', 54);
    if (data.getUint32(head.offset + 12) != 0x5f0f3cf5) {
      _invalid();
    }
    final unitsPerEm = data.getUint16(head.offset + 18);
    if (unitsPerEm < 16 || unitsPerEm > 16384) {
      _invalid();
    }
    final maxp = require('maxp', version == 0x00010000 ? 32 : 6);
    final glyphCount = data.getUint16(maxp.offset + 4);
    final hhea = require('hhea', 36);
    final metricsCount = data.getUint16(hhea.offset + 34);
    if (glyphCount == 0 || metricsCount == 0 || metricsCount > glyphCount) {
      _invalid();
    }
    require('hmtx', metricsCount * 4 + (glyphCount - metricsCount) * 2);
    require('OS/2', 78);
    require('post', 32);
    _validateName(data, require('name', 6));
    _validateCmap(data, require('cmap', 4));
    if (version == 0x00010000) {
      final glyf = require('glyf', 0);
      final format = data.getInt16(head.offset + 50);
      if (format != 0 && format != 1) {
        _invalid();
      }
      final stride = format == 0 ? 2 : 4;
      final loca = require('loca', (glyphCount + 1) * stride);
      var previousOffset = 0;
      for (var index = 0; index <= glyphCount; index++) {
        final offset = format == 0
            ? data.getUint16(loca.offset + index * 2) * 2
            : data.getUint32(loca.offset + index * 4);
        if (offset < previousOffset || offset > glyf.length) {
          _invalid();
        }
        previousOffset = offset;
      }
    } else {
      final cff = tables['CFF '];
      final cff2 = tables['CFF2'];
      if (cff != null) {
        if (cff.length < 4 ||
            data.getUint8(cff.offset) != 1 ||
            data.getUint8(cff.offset + 2) < 4 ||
            data.getUint8(cff.offset + 2) > cff.length) {
          _invalid();
        }
      } else if (cff2 != null) {
        if (cff2.length < 5 ||
            data.getUint8(cff2.offset) != 2 ||
            data.getUint8(cff2.offset + 2) < 5 ||
            data.getUint8(cff2.offset + 2) > cff2.length) {
          _invalid();
        }
      } else {
        _invalid();
      }
    }

    var displayName = baseName
        .substring(0, extensionAt)
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .trim();
    if (displayName.isEmpty) {
      displayName = baseName.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    }
    if (displayName.length > 256) {
      final lastUnit = displayName.codeUnitAt(255);
      displayName = displayName.substring(
        0,
        lastUnit >= 0xd800 && lastUnit <= 0xdbff ? 255 : 256,
      );
    }
    final id = sha256.convert(bytes).toString();
    return ImportedFont(
      id: id,
      displayName: displayName,
      storageFileName: '$id.${version == 0x00010000 ? 'ttf' : 'otf'}',
      byteLength: bytes.length,
    );
  }

  static void _validateName(ByteData data, _FontTable table) {
    final format = data.getUint16(table.offset);
    final count = data.getUint16(table.offset + 2);
    final stringsOffset = data.getUint16(table.offset + 4);
    if (format > 1 ||
        count == 0 ||
        6 + count * 12 > table.length ||
        stringsOffset < 6 + count * 12 ||
        stringsOffset > table.length) {
      _invalid();
    }
    for (var index = 0; index < count; index++) {
      final record = table.offset + 6 + index * 12;
      final length = data.getUint16(record + 8);
      final offset = data.getUint16(record + 10);
      if (offset + length > table.length - stringsOffset) {
        _invalid();
      }
    }
  }

  static void _validateCmap(ByteData data, _FontTable table) {
    final count = data.getUint16(table.offset + 2);
    final recordsEnd = 4 + count * 8;
    if (data.getUint16(table.offset) != 0 ||
        count == 0 ||
        recordsEnd > table.length) {
      _invalid();
    }
    var hasMapping = false;
    for (var index = 0; index < count; index++) {
      final offset = data.getUint32(table.offset + 4 + index * 8 + 4);
      if (offset < recordsEnd || offset > table.length - 2) {
        _invalid();
      }
      final start = table.offset + offset;
      final format = data.getUint16(start);
      final int length;
      if (format == 0 || format == 2 || format == 4 || format == 6) {
        if (offset > table.length - 4) {
          _invalid();
        }
        length = data.getUint16(start + 2);
      } else if (format == 8 || format == 10 || format == 12 || format == 13) {
        if (offset > table.length - 8) {
          _invalid();
        }
        length = data.getUint32(start + 4);
      } else if (format == 14) {
        if (offset > table.length - 6) {
          _invalid();
        }
        length = data.getUint32(start + 2);
      } else {
        continue;
      }
      final minimumLength = switch (format) {
        0 => 262,
        2 => 518,
        4 => 16,
        6 => 10,
        8 => 8208,
        10 => 20,
        12 || 13 => 16,
        14 => 10,
        _ => throw StateError('Unreachable cmap format'),
      };
      if (length < minimumLength || length > table.length - offset) {
        _invalid();
      }
      final mappingLength = switch (format) {
        6 => 10 + data.getUint16(start + 8) * 2,
        8 => 8208 + data.getUint32(start + 8204) * 12,
        10 => 20 + data.getUint32(start + 16) * 2,
        12 || 13 => 16 + data.getUint32(start + 12) * 12,
        14 => 10 + data.getUint32(start + 6) * 11,
        _ => minimumLength,
      };
      if (mappingLength > length) {
        _invalid();
      }
      if (format == 4) {
        final segmentCountX2 = data.getUint16(start + 6);
        if (segmentCountX2 == 0 ||
            segmentCountX2.isOdd ||
            16 + segmentCountX2 * 4 > length) {
          _invalid();
        }
      }
      if (format != 14) {
        hasMapping = true;
      }
    }
    if (!hasMapping) {
      _invalid();
    }
  }

  static Never _invalid() =>
      throw const FontLibraryException(FontLibraryFailure.invalidFont);
}

final class _FontTable {
  const _FontTable(this.offset, this.length);

  final int offset;
  final int length;
}
