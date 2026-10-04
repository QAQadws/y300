import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/html_pagination_core/html_pagination_core.dart';

void main() {
  test('source coordinates round trip at Unicode code-point boundaries', () {
    const text = ' A😀e\u0301🇨🇳 ';
    const boundaries = <int>[0, 1, 2, 4, 5, 6, 8, 10, 11];
    for (var codePoint = 0; codePoint < boundaries.length; codePoint++) {
      final utf16 = boundaries[codePoint];
      expect(
        HtmlTextCoordinates.codePointOffsetForUtf16(text, utf16),
        codePoint,
      );
      expect(
        HtmlTextCoordinates.utf16OffsetForCodePoint(text, codePoint),
        utf16,
      );
    }
    expect(HtmlTextCoordinates.codePointOffsetForUtf16(text, 3), 2);
    expect(HtmlTextCoordinates.codePointOffsetForUtf16(text, -1), 0);
    expect(HtmlTextCoordinates.codePointOffsetForUtf16(text, 100), 8);
    expect(HtmlTextCoordinates.utf16OffsetForCodePoint(text, -1), 0);
    expect(HtmlTextCoordinates.utf16OffsetForCodePoint(text, 100), 11);
    expect(HtmlTextCoordinates.codePointOffsetForUtf16('', 1), 0);
    expect(HtmlTextCoordinates.utf16OffsetForCodePoint('', 1), 0);
  });

  test(
    'snippet keeps complete family emoji and combining accents in context',
    () {
      const family = '👩‍👩‍👧‍👦';
      const text = 'x${family}Ke\u0301z';
      const start = 1 + family.length;
      expect(
        HtmlTextCoordinates.snippet(
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
        HtmlTextCoordinates.snippet(
          text: 'x🇨🇳y',
          start: 2,
          end: 3,
          contextLength: 0,
        ),
        '...🇨🇳...',
      );
      expect(
        HtmlTextCoordinates.snippet(
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
      HtmlTextCoordinates.snippet(text: '  A😀  ', start: -10, end: 100),
      '  A😀  ',
    );
    expect(
      HtmlTextCoordinates.snippet(
        text: 'abcdef',
        start: 2,
        end: 3,
        contextLength: -1,
      ),
      '...c...',
    );
    expect(HtmlTextCoordinates.snippet(text: '', start: 1, end: 2), '');
  });
}
