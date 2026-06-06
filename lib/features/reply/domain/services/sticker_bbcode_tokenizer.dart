import 'package:y300/features/reply/domain/models/reply_models.dart';

class StickerBbCodeTokenizer {
  const StickerBbCodeTokenizer();

  static const String previewTag = 'y300sticker';

  String encodeForPreview(String source, List<StickerItem> stickers) {
    if (source.isEmpty || stickers.isEmpty) {
      return source;
    }
    final codes = stickers
        .map((sticker) => sticker.code)
        .where((code) => code.trim().isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    if (codes.isEmpty) {
      return source;
    }

    final pattern = RegExp(codes.map(RegExp.escape).join('|'));
    return source.replaceAllMapped(pattern, (match) {
      final code = match.group(0)!;
      return '[$previewTag]$code[/$previewTag]';
    });
  }
}
