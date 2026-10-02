import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

/// Lossless plain text plus forum stickers, without interpreting BBCode tags.
class ComposerStickerTextCodec {
  const ComposerStickerTextCodec();

  Document decodeDocument(
    String source, {
    Iterable<String> stickerCodes = const [],
  }) {
    // The final newline belongs to Quill, including when the user already
    // supplied trailing newlines. Encoding removes exactly this sentinel.
    return Document.fromDelta(
      decodeFragment(source, stickerCodes: stickerCodes)..insert('\n'),
    );
  }

  Delta decodeFragment(
    String source, {
    Iterable<String> stickerCodes = const [],
  }) {
    final delta = Delta();
    final codes = stickerCodes.where((code) => code.isNotEmpty).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (codes.isEmpty) {
      if (source.isNotEmpty) delta.insert(source);
      return delta;
    }
    final pattern = RegExp(codes.map(RegExp.escape).join('|'));
    var offset = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > offset) {
        delta.insert(source.substring(offset, match.start));
      }
      delta.insert(composerQuillStickerEmbedData(match.group(0)!));
      offset = match.end;
    }
    if (offset < source.length) {
      delta.insert(source.substring(offset));
    }
    return delta;
  }

  String encodeDocument(Document document) {
    final buffer = StringBuffer();
    for (final operation in document.toDelta().toList()) {
      final data = operation.data;
      if (data is String) {
        buffer.write(data);
      } else {
        final code = composerQuillEmbedData(
          data,
          composerQuillStickerEmbedType,
        );
        if (code == null) {
          throw StateError('Unsupported embed in sticker input');
        }
        buffer.write(code);
      }
    }
    final source = buffer.toString();
    return source.endsWith('\n')
        ? source.substring(0, source.length - 1)
        : source;
  }
}
