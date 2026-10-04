import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_reader_text_coordinates.dart';

void main() {
  test('source coordinates round trip at Unicode code-point boundaries', () {
    const text = ' A😀e\u0301🇨🇳 ';
    const boundaries = <int>[0, 1, 2, 4, 5, 6, 8, 10, 11];
    for (var codePoint = 0; codePoint < boundaries.length; codePoint++) {
      final utf16 = boundaries[codePoint];
      expect(
        NovelReaderTextCoordinates.codePointOffsetForUtf16(text, utf16),
        codePoint,
      );
      expect(
        NovelReaderTextCoordinates.utf16OffsetForCodePoint(text, codePoint),
        utf16,
      );
    }
    expect(NovelReaderTextCoordinates.codePointOffsetForUtf16(text, 3), 2);
    expect(NovelReaderTextCoordinates.codePointOffsetForUtf16(text, -1), 0);
    expect(NovelReaderTextCoordinates.codePointOffsetForUtf16(text, 100), 8);
    expect(NovelReaderTextCoordinates.utf16OffsetForCodePoint(text, -1), 0);
    expect(NovelReaderTextCoordinates.utf16OffsetForCodePoint(text, 100), 11);
    expect(NovelReaderTextCoordinates.codePointOffsetForUtf16('', 1), 0);
    expect(NovelReaderTextCoordinates.utf16OffsetForCodePoint('', 1), 0);
  });

  test(
    'snippet keeps complete family emoji and combining accents in context',
    () {
      const family = '👩‍👩‍👧‍👦';
      const text = 'x${family}Ke\u0301z';
      const start = 1 + family.length;
      expect(
        NovelReaderTextCoordinates.snippet(
          text: text,
          start: start,
          end: start + 1,
          contextLength: 1,
        ),
        '...${family}Ke\u0301...',
      );
    },
  );

  test(
    'snippet expands match endpoints inside flag and combining graphemes',
    () {
      expect(
        NovelReaderTextCoordinates.snippet(
          text: 'x🇨🇳y',
          start: 2,
          end: 3,
          contextLength: 0,
        ),
        '...🇨🇳...',
      );
      expect(
        NovelReaderTextCoordinates.snippet(
          text: 'xe\u0301y',
          start: 2,
          end: 3,
          contextLength: 0,
        ),
        '...e\u0301...',
      );
    },
  );

  test('snippet clamps source ranges without trimming its whitespace', () {
    expect(
      NovelReaderTextCoordinates.snippet(text: '  A😀  ', start: -10, end: 100),
      '  A😀  ',
    );
    expect(
      NovelReaderTextCoordinates.snippet(
        text: 'abcdef',
        start: 2,
        end: 3,
        contextLength: -1,
      ),
      '...c...',
    );
    expect(NovelReaderTextCoordinates.snippet(text: '', start: 1, end: 2), '');
  });
}
