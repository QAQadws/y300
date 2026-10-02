/// Parses only the bounded object/string/integer subset emitted by Discuz's
/// friend selector. This is data parsing, never JavaScript evaluation.
final class DiscuzFriendLiteralParser {
  /// Parses a complete literal and rejects expressions and duplicate keys.
  Map<String, Object?> parse(String source) {
    if (source.length > 131072) throw const FormatException('friend_size');
    final reader = _Reader(source);
    final result = reader.object(0);
    reader.whitespace();
    if (reader.index != source.length) {
      throw const FormatException('friend_trailing');
    }
    return result;
  }
}

final class _Reader {
  _Reader(this.source);
  final String source;
  int index = 0;
  int fields = 0;

  void whitespace() {
    while (index < source.length &&
        const [9, 10, 13, 32].contains(source.codeUnitAt(index))) {
      index++;
    }
  }

  String get char => index < source.length ? source[index] : '';

  void take(String expected) {
    whitespace();
    if (char != expected) throw const FormatException('friend_syntax');
    index++;
  }

  Map<String, Object?> object(int depth) {
    if (depth > 3) throw const FormatException('friend_depth');
    take('{');
    final result = <String, Object?>{};
    whitespace();
    if (char == '}') {
      index++;
      return result;
    }
    while (true) {
      whitespace();
      final key = char == "'" || char == '"' ? string() : integer().toString();
      if (++fields > 128 || result.containsKey(key)) {
        throw const FormatException('friend_fields');
      }
      take(':');
      whitespace();
      result[key] = char == '{'
          ? object(depth + 1)
          : char == "'" || char == '"'
          ? string()
          : integer();
      whitespace();
      if (char == '}') {
        index++;
        return result;
      }
      take(',');
    }
  }

  int integer() {
    final start = index;
    while (index < source.length &&
        source.codeUnitAt(index) >= 48 &&
        source.codeUnitAt(index) <= 57) {
      index++;
    }
    final raw = source.substring(start, index);
    if (raw.isEmpty || raw.length > 12 || (raw.length > 1 && raw[0] == '0')) {
      throw const FormatException('friend_integer');
    }
    return int.parse(raw);
  }

  String string() {
    final quote = char;
    index++;
    final result = StringBuffer();
    while (index < source.length) {
      var current = source[index++];
      if (current == quote) return result.toString();
      if (current.codeUnitAt(0) < 32) {
        throw const FormatException('friend_string');
      }
      if (current == r'\') {
        if (index == source.length) {
          throw const FormatException('friend_escape');
        }
        current = source[index++];
        switch (current) {
          case "'":
          case '"':
          case r'\':
          case '/':
            result.write(current);
          case 'n':
            result.write('\n');
          case 'r':
            result.write('\r');
          case 't':
            result.write('\t');
          case 'b':
            result.write('\b');
          case 'f':
            result.write('\f');
          case '0':
            result.writeCharCode(0);
          case 'x':
          case 'u':
            final length = current == 'x' ? 2 : 4;
            if (index + length > source.length) {
              throw const FormatException('friend_escape');
            }
            final raw = source.substring(index, index + length);
            if (!RegExp(r'^[a-fA-F0-9]+$').hasMatch(raw)) {
              throw const FormatException('friend_escape');
            }
            result.writeCharCode(int.parse(raw, radix: 16));
            index += length;
          default:
            throw const FormatException('friend_escape');
        }
      } else {
        result.write(current);
      }
      if (result.length > 16384) throw const FormatException('friend_string');
    }
    throw const FormatException('friend_string');
  }
}
