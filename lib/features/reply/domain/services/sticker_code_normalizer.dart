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
