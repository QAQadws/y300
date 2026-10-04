import 'package:characters/characters.dart';

/// Coordinates always refer to the source text, including its whitespace.
abstract final class NovelReaderTextCoordinates {
  /// An offset inside a surrogate pair resolves to that code point's beginning.
  static int codePointOffsetForUtf16(String text, int offset) {
    final target = offset.clamp(0, text.length).toInt();
    var utf16Offset = 0;
    var codePointOffset = 0;
    for (final rune in text.runes) {
      final next = utf16Offset + (rune > 0xffff ? 2 : 1);
      if (next > target) {
        break;
      }
      utf16Offset = next;
      codePointOffset++;
    }
    return codePointOffset;
  }

  static int utf16OffsetForCodePoint(String text, int offset) {
    if (offset <= 0) {
      return 0;
    }
    var utf16Offset = 0;
    var codePointOffset = 0;
    for (final rune in text.runes) {
      utf16Offset += rune > 0xffff ? 2 : 1;
      if (++codePointOffset == offset) {
        break;
      }
    }
    return utf16Offset;
  }

  /// [start], [end] and [contextLength] use source UTF-16 code units. The window
  /// expands to whole graphemes so neither the match nor its context is cut.
  static String snippet({
    required String text,
    required int start,
    required int end,
    int contextLength = 18,
  }) {
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    final safeContext = contextLength < 0 ? 0 : contextLength;
    final windowStart = (safeStart - safeContext).clamp(0, text.length).toInt();
    final windowEnd = (safeEnd + safeContext).clamp(0, text.length).toInt();
    var snippetStart = 0;
    var snippetEnd = 0;
    var offset = 0;
    for (final character in text.characters) {
      final next = offset + character.length;
      if (next <= windowStart) {
        snippetStart = next;
      }
      if (offset >= windowEnd) {
        break;
      }
      snippetEnd = next;
      offset = next;
    }
    final prefix = snippetStart > 0 ? '...' : '';
    final suffix = snippetEnd < text.length ? '...' : '';
    return '$prefix${text.substring(snippetStart, snippetEnd)}$suffix';
  }
}
