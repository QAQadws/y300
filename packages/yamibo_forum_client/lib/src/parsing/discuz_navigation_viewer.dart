/// Reads a unique static viewer declaration from public head scripts.
///
/// This recognizes the template's top-level `var` statement without executing
/// JavaScript. Comments and string literals cannot supply assignments. Dynamic
/// expressions, regex literals, and template interpolation are unsupported.
String? discuzNavigationViewer(Iterable<String> scripts) {
  String? viewer;
  var assignments = 0;
  for (final source in scripts) {
    if (!source.contains('discuz_uid')) continue;
    final tokens = _tokens(source);
    if (tokens == null) return null;
    if (!tokens.any((token) => !token.literal && token.value == 'discuz_uid')) {
      continue;
    }
    var index = 0;
    // Only the template's static declaration grammar is supported. Conditional
    // or later mutations must not masquerade as an executed viewer assignment.
    while (index < tokens.length) {
      if (tokens[index].literal || tokens[index++].value != 'var') return null;
      while (true) {
        if (index + 2 >= tokens.length) return null;
        final name = tokens[index++];
        final equals = tokens[index++];
        final value = tokens[index++];
        if (name.literal ||
            _identifier.stringMatch(name.value) != name.value ||
            equals.literal ||
            equals.value != '=' ||
            !value.literal) {
          return null;
        }
        if (name.value == 'discuz_uid') {
          assignments++;
          if (!value.staticString ||
              _positiveId.stringMatch(value.value) != value.value) {
            return null;
          }
          viewer = value.value;
        }
        if (index == tokens.length) break;
        final separator = tokens[index++];
        if (separator.literal) return null;
        if (separator.value == ';') break;
        if (separator.value != ',') return null;
      }
    }
  }
  return assignments == 1 ? viewer : null;
}

List<_Token>? _tokens(String source) {
  final tokens = <_Token>[];
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    if (_whitespace.hasMatch(char)) {
      index++;
      continue;
    }
    if (source.startsWith('//', index)) {
      index += 2;
      while (index < source.length &&
          source[index] != '\n' &&
          source[index] != '\r') {
        index++;
      }
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      if (end < 0) return null;
      index = end + 2;
      continue;
    }
    if (char == "'" || char == '"' || char == '`') {
      final quote = char;
      final start = ++index;
      var closed = false;
      while (index < source.length) {
        if (quote == '`' && source.startsWith(r'${', index)) return null;
        if (source[index] == '\\') {
          index += 2;
          continue;
        }
        if (source[index] == quote) {
          closed = true;
          break;
        }
        if (quote != '`' && (source[index] == '\n' || source[index] == '\r')) {
          return null;
        }
        index++;
      }
      if (!closed) return null;
      tokens.add(
        _Token(
          source.substring(start, index),
          literal: true,
          staticString: quote != '`',
        ),
      );
      index++;
      continue;
    }
    // A slash outside comments/strings could open a regex. Decline instead of
    // interpreting its contents as code; the supported declaration needs none.
    if (char == '/') return null;
    if (_word.hasMatch(char)) {
      final start = index++;
      while (index < source.length && _word.hasMatch(source[index])) {
        index++;
      }
      tokens.add(_Token(source.substring(start, index)));
      continue;
    }
    tokens.add(_Token(char));
    index++;
  }
  return tokens;
}

final _positiveId = RegExp(r'^[1-9][0-9]*$');
final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
final _word = RegExp(r'[A-Za-z0-9_$]');
final _whitespace = RegExp(r'\s');

final class _Token {
  const _Token(this.value, {this.literal = false, this.staticString = false});

  final String value;
  final bool literal;
  final bool staticString;
}
