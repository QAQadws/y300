/// 表情码归一化器：把表情清单中形如 `/\{\:9_656\:\}/` 的正则模式
/// 还原成实际可识别的 BBCode（`{:9_656:}`）。
class StickerCodeNormalizer {
  const StickerCodeNormalizer();

  String normalize(String rawCodePattern) {
    var normalized = rawCodePattern.trim();
    if (normalized.length >= 2 &&
        normalized.startsWith('/') &&
        normalized.endsWith('/')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized
        .replaceAll(r'\{', '{')
        .replaceAll(r'\}', '}')
        .replaceAll(r'\:', ':');
  }
}
