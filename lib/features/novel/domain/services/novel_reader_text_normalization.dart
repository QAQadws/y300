/// The semantic parser's whitespace rules, with source-rune mapping.
/// Entity decoding belongs to the DOM parser, before this projection.
final class NovelReaderTextNormalization {
  NovelReaderTextNormalization._(this.text, this.offsets);

  final String text;
  final List<int> offsets;

  static String normalize(String source, {bool trim = false}) {
    final text = source
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n');
    return trim ? text.trim() : text;
  }

  factory NovelReaderTextNormalization.project(
    String source, {
    bool trim = false,
  }) {
    final input = source.runes.toList(growable: false);
    final output = <int>[];
    final boundaries = <int>[0];
    for (var index = 0; index < input.length; index++) {
      final rune = input[index] == 0xA0 ? 0x20 : input[index];
      if (rune == 0x0D) {
        output.add(0x0A);
        boundaries.add(output.length);
        if (index + 1 < input.length && input[index + 1] == 0x0A) {
          index++;
          boundaries.add(output.length);
        }
      } else if (rune == 0x20 || rune == 0x09) {
        if (output.isEmpty || (output.last != 0x20 && output.last != 0x0A)) {
          output.add(0x20);
        }
        boundaries.add(output.length);
      } else {
        output.add(rune);
        boundaries.add(output.length);
      }
    }
    var start = 0;
    var end = output.length;
    if (trim) {
      while (start < end && String.fromCharCode(output[start]).trim().isEmpty) {
        start++;
      }
      while (end > start &&
          String.fromCharCode(output[end - 1]).trim().isEmpty) {
        end--;
      }
    }
    return NovelReaderTextNormalization._(
      String.fromCharCodes(output.sublist(start, end)),
      List<int>.unmodifiable(
        boundaries.map((offset) => (offset - start).clamp(0, end - start)),
      ),
    );
  }
}
