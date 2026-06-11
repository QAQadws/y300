/// 表情包领域模型。表情清单来自 `assets/stickers/stickers.json`，
/// 其 BBCode 形式（如 `{:9_656:}`）被回复页与发帖页共用。
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
    required this.assetPath,
    required this.rawCodePattern,
  });

  final String code;
  final String assetPath;
  final String rawCodePattern;
}
