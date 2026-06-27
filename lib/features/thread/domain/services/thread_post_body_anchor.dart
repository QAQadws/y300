String threadPostBodyAnchorId(String prefix, String seed) {
  var hash = 0x811c9dc5;
  for (final codeUnit in seed.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return '$prefix-${hash.toRadixString(16).padLeft(8, '0')}';
}
