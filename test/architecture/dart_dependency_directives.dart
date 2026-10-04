import 'package:path/path.dart' as p;

String resolveDartDependencyTarget(String source, String target) {
  if (target.startsWith('package:y300/')) {
    return p.posix.normalize('lib/${target.substring('package:y300/'.length)}');
  }
  if (Uri.parse(target).hasScheme) return target;
  return p.posix.normalize(p.posix.join(p.posix.dirname(source), target));
}

String normalizeDartSourcePath(String path) =>
    p.posix.normalize(path.replaceAll('\\', '/'));

Iterable<String> dartDependencyDirectiveUris(String source) sync* {
  final tokens = _sourceTokens(source).toList();
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.isString || !{'import', 'export', 'part'}.contains(token.text)) {
      continue;
    }
    var expectsUri = true;
    var parentheses = 0;
    while (++index < tokens.length && tokens[index].text != ';') {
      final next = tokens[index];
      if (next.isString) {
        if (expectsUri && parentheses == 0) yield next.text;
        expectsUri = false;
      } else if (next.text == '(') {
        parentheses++;
      } else if (next.text == ')') {
        parentheses--;
        // A conditional directive's URI follows its closing parenthesis;
        // string values inside the condition are configuration, not imports.
        if (parentheses == 0) expectsUri = true;
      }
    }
  }
}

/// A null list means that an export has no explicit show combinator.
Iterable<List<String>?> dartExportShowLists(String source) sync* {
  final tokens = _sourceTokens(source).toList();
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.isString || token.text != 'export') continue;
    List<String>? names;
    var showing = false;
    var parentheses = 0;
    while (++index < tokens.length && tokens[index].text != ';') {
      final next = tokens[index];
      if (next.isString) continue;
      if (next.text == '(') parentheses++;
      if (next.text == ')') parentheses--;
      if (parentheses != 0) continue;
      if (next.text == 'show') {
        names ??= <String>[];
        showing = true;
      } else if (next.text == 'hide') {
        showing = false;
      } else if (showing && _isIdentifierCode(next.text.codeUnitAt(0))) {
        names!.add(next.text);
      }
    }
    yield names;
  }
}

class _SourceToken {
  const _SourceToken(this.text, {this.isString = false});

  final String text;
  final bool isString;
}

// A small lexer keeps quoted examples and nested comments out of the guard
// without adding an analyzer dependency just to inspect URI directives.
Iterable<_SourceToken> _sourceTokens(String source) sync* {
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      index = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      continue;
    }
    final raw =
        source[index] == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"');
    final quoteIndex = raw ? index + 1 : index;
    final quote = source[quoteIndex];
    if (quote == "'" || quote == '"') {
      final delimiter = source.startsWith(quote * 3, quoteIndex)
          ? quote * 3
          : quote;
      final start = quoteIndex + delimiter.length;
      index = start;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        if (!raw && source[index] == '\\') {
          index += 2;
        } else {
          index++;
        }
      }
      final value = source.substring(
        start,
        index < source.length ? index : source.length,
      );
      yield _SourceToken(raw ? value : _unescape(value), isString: true);
      index += delimiter.length;
      continue;
    }
    if (_isIdentifierCode(source.codeUnitAt(index))) {
      final start = index++;
      while (index < source.length &&
          _isIdentifierCode(source.codeUnitAt(index))) {
        index++;
      }
      yield _SourceToken(source.substring(start, index));
    } else {
      if (source[index].trim().isNotEmpty) yield _SourceToken(source[index]);
      index++;
    }
  }
}

bool _isIdentifierCode(int code) =>
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    (code >= 48 && code <= 57) ||
    code == 95 ||
    code == 36;

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)'),
  (match) {
    final escape = match[1]!;
    if (escape.startsWith('u{')) {
      return String.fromCharCode(
        int.parse(escape.substring(2, escape.length - 1), radix: 16),
      );
    }
    if (escape.startsWith('u') || escape.startsWith('x')) {
      return String.fromCharCode(int.parse(escape.substring(1), radix: 16));
    }
    return switch (escape) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      _ => escape,
    };
  },
);
