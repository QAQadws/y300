import 'package:forum_markup_core/forum_markup_core.dart';

final class PostEditMessageCanonicalizer {
  const PostEditMessageCanonicalizer();

  String canonicalize(String message) {
    final normalized = message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    const grammar = ComposerAttachBbCodeGrammar();
    if (grammar.scan(normalized).isEmpty) {
      return normalized;
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final token in grammar.scan(normalized)) {
      buffer
        ..write(normalized.substring(cursor, token.start))
        ..write('[attach]${token.aid}[/attach]');
      cursor = token.end;
    }
    buffer.write(normalized.substring(cursor));
    return buffer.toString();
  }
}
