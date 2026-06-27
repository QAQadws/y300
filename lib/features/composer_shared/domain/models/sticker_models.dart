/// 表情包领域模型。表情清单以论坛远端 catalog 为真源，BBCode 形式
///（如 `{:9_656:}`）被回复页与发帖页共用。
class StickerGroup {
  const StickerGroup({
    required this.id,
    required this.title,
    required this.stickers,
  });

  final String id;
  final String title;
  final List<StickerItem> stickers;
}

class StickerItem {
  const StickerItem({
    required this.code,
    required this.rawCodePattern,
    required this.imagePath,
    required this.imageUrl,
    required this.cacheKey,
  });

  final String code;
  final String rawCodePattern;
  final String imagePath;
  final String imageUrl;
  final String cacheKey;
}
