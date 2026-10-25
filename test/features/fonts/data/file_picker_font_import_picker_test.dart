import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/fonts/data/services/file_picker_font_import_picker.dart';
import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';

void main() {
  test('a cancelled picker returns no import', () async {
    var selections = 0;
    final picker = FilePickerFontImportPicker(
      pickFile: () async {
        selections++;
        return null;
      },
    );

    expect(await picker.pickFont(), isNull);
    expect(selections, 1);
  });

  test(
    'reads selected bytes as a bounded stream without asking for a path',
    () async {
      final first = Uint8List.fromList(<int>[1, 2]);
      final second = Uint8List.fromList(<int>[3, 4]);
      final file = _FontPlatformFile(
        name: 'Reading.ttf',
        knownLength: 4,
        readStream: () =>
            Stream<Uint8List>.fromIterable(<Uint8List>[first, second]),
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      final result = await picker.pickFont();

      expect(result, isNotNull);
      expect(result!.fileName, 'Reading.ttf');
      expect(result.bytes, <int>[1, 2, 3, 4]);
      expect(file.streamReads, 1);
      expect(file.fullReads, 0);
      expect(() => result.bytes[0] = 9, throwsUnsupportedError);
      first.fillRange(0, first.length, 0);
      second.fillRange(0, second.length, 0);
      expect(result.bytes, <int>[1, 2, 3, 4]);
    },
  );

  test(
    'owns the returned snapshot when a provider emits a single buffer',
    () async {
      final source = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final file = _FontPlatformFile(
        name: 'Reading.ttf',
        knownLength: source.length,
        readStream: () => Stream<Uint8List>.value(source),
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      final result = await picker.pickFont();
      source.fillRange(0, source.length, 9);

      expect(result!.bytes, <int>[1, 2, 3, 4]);
      expect(() => result.bytes[0] = 9, throwsUnsupportedError);
    },
  );

  test(
    'snapshots each chunk when the provider reuses its mutable buffer',
    () async {
      final buffer = Uint8List.fromList(<int>[1, 2]);
      Stream<Uint8List> source() async* {
        yield buffer;
        buffer.setAll(0, <int>[3, 4]);
        yield buffer;
      }

      final file = _FontPlatformFile(
        name: 'Reading.ttf',
        knownLength: 4,
        readStream: source,
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      final result = await picker.pickFont();

      expect(result!.bytes, <int>[1, 2, 3, 4]);
    },
  );

  for (final name in <String>['Reading.TTF', 'Reading.OTF']) {
    test('accepts the supported extension case-insensitively: $name', () async {
      final file = _FontPlatformFile(
        name: name,
        knownLength: 1,
        readStream: () => Stream<Uint8List>.value(Uint8List.fromList(<int>[1])),
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      final result = await picker.pickFont();

      expect(result!.fileName, name);
      expect(result.bytes, <int>[1]);
      expect(file.streamReads, 1);
    });
  }

  test('rejects unsupported extensions before opening a stream', () async {
    for (final name in <String>[
      'Reading.woff',
      'Reading.ttc',
      'Reading.ttf.exe',
      'Reading',
    ]) {
      final file = _FontPlatformFile(
        name: name,
        knownLength: 1,
        readStream: () => throw StateError('must not read an unsupported file'),
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      await expectLater(
        picker.pickFont(),
        _throwsCode(FontLibraryFailure.unsupportedFormat),
        reason: name,
      );
      expect(file.streamReads, 0, reason: name);
      expect(file.fullReads, 0, reason: name);
    }
  });

  test(
    'rejects an advertised oversized file before opening its stream',
    () async {
      final file = _FontPlatformFile(
        name: 'Reading.ttf',
        knownLength: FontFileValidator.maxFontBytes + 1,
        readStream: () => throw StateError('must not read an oversized file'),
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      await expectLater(
        picker.pickFont(),
        _throwsCode(FontLibraryFailure.tooLarge),
      );
      expect(file.streamReads, 0);
      expect(file.fullReads, 0);
    },
  );

  for (final knownLength in <int?>[null, 1]) {
    test(
      'bounds actual accumulated bytes and cancels when reported length is $knownLength',
      () async {
        const chunkSize = 1024 * 1024;
        final chunk = Uint8List(chunkSize);
        var cancelled = false;
        var readPastOverflow = false;
        Stream<Uint8List> source() async* {
          try {
            for (
              var index = 0;
              index < FontFileValidator.maxFontBytes ~/ chunkSize;
              index++
            ) {
              yield chunk;
            }
            yield Uint8List(1);
            readPastOverflow = true;
          } finally {
            cancelled = true;
          }
        }

        final file = _FontPlatformFile(
          name: 'Reading.ttf',
          knownLength: knownLength,
          readStream: source,
        );
        final picker = FilePickerFontImportPicker(pickFile: () async => file);

        await expectLater(
          picker.pickFont(),
          _throwsCode(FontLibraryFailure.tooLarge),
        );

        expect(cancelled, isTrue);
        expect(readPastOverflow, isFalse);
        expect(file.streamReads, 1);
        expect(file.fullReads, 0);
      },
    );
  }

  test('maps picker failures to typed storage failure', () async {
    final picker = FilePickerFontImportPicker(
      pickFile: () async => throw StateError('private picker diagnostics'),
    );

    await expectLater(
      picker.pickFont(),
      _throwsCode(FontLibraryFailure.storage),
    );
  });

  test('maps stream creation failures to typed storage failure', () async {
    final file = _FontPlatformFile(
      name: 'Reading.ttf',
      knownLength: null,
      readStream: () => throw StateError('private provider diagnostics'),
    );
    final picker = FilePickerFontImportPicker(pickFile: () async => file);

    await expectLater(
      picker.pickFont(),
      _throwsCode(FontLibraryFailure.storage),
    );
    expect(file.streamReads, 1);
  });

  test(
    'maps stream errors to storage failure and releases the stream',
    () async {
      var cancelled = false;
      Stream<Uint8List> source() async* {
        try {
          yield Uint8List.fromList(<int>[1, 2]);
          throw StateError('private stream diagnostics');
        } finally {
          cancelled = true;
        }
      }

      final file = _FontPlatformFile(
        name: 'Reading.ttf',
        knownLength: null,
        readStream: source,
      );
      final picker = FilePickerFontImportPicker(pickFile: () async => file);

      await expectLater(
        picker.pickFont(),
        _throwsCode(FontLibraryFailure.storage),
      );
      expect(cancelled, isTrue);
    },
  );
}

final class _FontPlatformFile extends PlatformFile {
  _FontPlatformFile({
    required this.name,
    required this.knownLength,
    required this.readStream,
  });

  @override
  final String name;
  final int? knownLength;
  final Stream<Uint8List> Function() readStream;
  int streamReads = 0;
  int fullReads = 0;

  @override
  int? lengthSync() => knownLength;

  @override
  Stream<Uint8List> readAsByteStream() {
    streamReads++;
    return readStream();
  }

  @override
  Future<Uint8List> readAsBytes() {
    fullReads++;
    throw StateError('The import must stream the selected file.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _throwsCode(FontLibraryFailure code) => throwsA(
  isA<FontLibraryException>().having((error) => error.code, 'code', code),
);
