/// How one actually emitted semantic run was obtained from its repaired DOM node.
/// This is neither a display offset nor evidence that a native page covers it.
enum NovelReaderSourceTextPolicy {
  trimmedTextNode,
  inlineTextNode,
  trimmedElementText,
  hardBreak,
}

final class NovelReaderTextSourceOrigin {
  const NovelReaderTextSourceOrigin({
    required this.path,
    required this.sourceText,
    required this.text,
    required this.nodeId,
    required this.semanticCodePointStart,
    required this.policy,
  });
  final String path;
  final String sourceText;
  final String text;
  final String nodeId;
  final int semanticCodePointStart;
  final NovelReaderSourceTextPolicy policy;
}

/// An actually emitted image block and its exact repaired DOM path. Images
/// have no textual source interval; an equal URL cannot identify another slot.
final class NovelReaderImageSourceOrigin {
  const NovelReaderImageSourceOrigin({
    required this.path,
    required this.nodeId,
    required this.rawSource,
  });
  final String path, nodeId, rawSource;
}

final class NovelReaderSourceProvenanceLimits {
  const NovelReaderSourceProvenanceLimits({
    this.maxEntries = 8192,
    this.maxSourceCodeUnits = 512 * 1024,
    this.maxPathCodeUnits = 64 * 1024,
  });
  final int maxEntries;
  final int maxSourceCodeUnits;
  final int maxPathCodeUnits;
}

/// Optional pure sidecar from the semantic parser's own walk. Hashes the exact
/// trimmed parse input with UTF-8 SHA-256, not the historical rawHtmlHash.
/// Conversion provenance remains the containing document's actual identity.
/// No HTML/DOM, dense per-rune maps, theme or reading owner is retained.
final class NovelReaderSourceProvenance {
  NovelReaderSourceProvenance({
    required this.inputHash,
    required Iterable<NovelReaderTextSourceOrigin> origins,
    Iterable<NovelReaderImageSourceOrigin> images = const [],
  }) : origins = List.unmodifiable(origins),
       images = List.unmodifiable(images);
  static const revision = 2;
  final String inputHash;
  final List<NovelReaderTextSourceOrigin> origins;
  final List<NovelReaderImageSourceOrigin> images;
}
