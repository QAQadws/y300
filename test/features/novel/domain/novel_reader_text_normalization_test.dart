import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_normalization.dart';

void main() {
  test(
    'preserves the semantic parser whitespace rules with a monotone source map',
    () {
      for (final sample in <(String, String)>[
        ('A\u00a0\u00a0B', 'A B'),
        ('A\r\n  B\r\tC', 'A\nB\nC'),
        ('  A\t\tB  ', ' A B '),
        ('　A　', '　A　'),
        ('e\u0301👩‍👩‍👧‍👦', 'e\u0301👩‍👩‍👧‍👦'),
      ]) {
        final projection = NovelReaderTextNormalization.project(sample.$1);
        expect(projection.text, sample.$2);
        expect(NovelReaderTextNormalization.normalize(sample.$1), sample.$2);
        expect(projection.offsets.length, sample.$1.runes.length + 1);
        expect(projection.offsets.first, 0);
        expect(projection.offsets.last, sample.$2.runes.length);
        expect(
          projection.offsets,
          orderedEquals(projection.offsets.toList()..sort()),
        );
        final trimmed = NovelReaderTextNormalization.project(
          sample.$1,
          trim: true,
        );
        expect(trimmed.text, sample.$2.trim());
        expect(
          NovelReaderTextNormalization.normalize(sample.$1, trim: true),
          sample.$2.trim(),
        );
        expect(trimmed.offsets.last, sample.$2.trim().runes.length);
      }
    },
  );

  test(
    'collapsed and deleted whitespace has an explicit semantic boundary',
    () {
      final projected = NovelReaderTextNormalization.project(
        '  A  B\n  C  ',
        trim: true,
      );
      expect(projected.text, 'A B\nC');
      expect(projected.offsets, <int>[0, 0, 0, 1, 2, 2, 3, 4, 4, 4, 5, 5, 5]);
    },
  );
}
