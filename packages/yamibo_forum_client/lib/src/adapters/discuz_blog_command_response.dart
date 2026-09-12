import 'package:html/parser.dart' as html;

/// A literal Discuz AJAX callback, never an evaluated script or server message.
final class DiscuzBlogCommandResponse {
  /// Creates a parsed callback.
  const DiscuzBlogCommandResponse({
    required this.applied,
    this.redirect,
    this.commentId,
  });

  /// Whether the server called the success handler.
  final bool applied;

  /// Server success destination, validated by the operation adapter.
  final String? redirect;

  /// Comment identity supplied in the callback values.
  final String? commentId;

  /// Accepts one actual callback invocation with literal arguments.
  /// Strings, handler declarations, unrelated scripts, and mixed results are
  /// not success evidence. This deliberately does not execute JavaScript.
  static DiscuzBlogCommandResponse? parse(String source, String handleKey) {
    var payload = source;
    if (source.contains('<![CDATA[')) {
      final envelope = RegExp(
        r'^\s*(?:<\?xml[^>]*\?>\s*)?<root>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</root>\s*$',
      ).firstMatch(source);
      if (envelope == null) return null;
      payload = envelope.group(1)!;
      if (payload.contains('<![CDATA[') || payload.contains(']]>')) return null;
    }
    final document = html.parse(payload);
    if (document.querySelector('form') != null) return null;
    final results = <DiscuzBlogCommandResponse>[];
    final guard = RegExp(
      '^\\s*if\\s*\\(\\s*typeof\\s+(succeedhandle|errorhandle)_${RegExp.escape(handleKey)}'
      r'''\s*==\s*['"]function['"]\s*\)\s*\{\s*'''
      '\\1_${RegExp.escape(handleKey)}\\s*\\(',
    );
    for (final script in document.querySelectorAll('script')) {
      final match = guard.firstMatch(script.text);
      if (match == null) continue;
      final reader = _LiteralReader(script.text)..offset = match.end;
      try {
        final success = match.group(1) == 'succeedhandle';
        final first = reader.string();
        reader.require(',');
        if (success) {
          reader.string();
          reader.require(',');
        }
        final values = reader.values();
        reader.require(')');
        reader.require(';');
        reader.require('}');
        if (guard.hasMatch(script.text.substring(reader.offset))) return null;
        results.add(
          DiscuzBlogCommandResponse(
            applied: success,
            redirect: success ? first : null,
            commentId: values['cid'],
          ),
        );
      } on FormatException {
        return null;
      }
    }
    return results.length == 1 ? results.single : null;
  }
}

final class _LiteralReader {
  _LiteralReader(this.source);
  final String source;
  int offset = 0;
  bool get done => offset >= source.length;
  bool get isQuote => !done && (source[offset] == "'" || source[offset] == '"');

  void space() {
    while (!done) {
      if (RegExp(r'\s').hasMatch(source[offset])) {
        offset++;
        continue;
      }
      if (source.startsWith('//', offset)) {
        final end = source.indexOf('\n', offset + 2);
        offset = end < 0 ? source.length : end + 1;
      } else if (source.startsWith('/*', offset)) {
        final end = source.indexOf('*/', offset + 2);
        if (end < 0) throw const FormatException('blog_callback_comment');
        offset = end + 2;
      } else {
        break;
      }
    }
  }

  bool consume(String value) {
    space();
    if (!source.startsWith(value, offset)) return false;
    offset += value.length;
    return true;
  }

  void require(String value) {
    if (!consume(value)) throw const FormatException('blog_callback_literal');
  }

  String string() {
    space();
    if (!isQuote) throw const FormatException('blog_callback_string');
    final quote = source[offset++];
    final result = StringBuffer();
    while (!done) {
      final char = source[offset++];
      if (char == quote) return result.toString();
      if (char != r'\') {
        result.write(char);
        continue;
      }
      if (done) break;
      final escaped = source[offset++];
      if (escaped == 'x' || escaped == 'u') {
        final length = escaped == 'x' ? 2 : 4;
        if (offset + length > source.length) break;
        final code = int.tryParse(
          source.substring(offset, offset + length),
          radix: 16,
        );
        if (code == null) break;
        result.writeCharCode(code);
        offset += length;
      } else {
        result.write(switch (escaped) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => escaped,
        });
      }
    }
    throw const FormatException('blog_callback_unclosed_string');
  }

  Map<String, String> values() {
    require('{');
    final result = <String, String>{};
    if (consume('}')) return result;
    do {
      final key = string();
      require(':');
      if (result.containsKey(key)) {
        throw const FormatException('blog_callback_duplicate_value');
      }
      result[key] = string();
      if (consume('}')) return result;
      require(',');
    } while (!done);
    throw const FormatException('blog_callback_unclosed_values');
  }
}
