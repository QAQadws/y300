import 'package:flutter/foundation.dart';

enum NovelReaderLegacyMarkupNormalizationReason {
  emptyFontFace,
  invalidQuoteOnlyFontFace,
  invalidNoUsableFontFamilyToken,
}

@immutable
final class NovelReaderLegacyMarkupNormalizationSummary {
  const NovelReaderLegacyMarkupNormalizationSummary({
    required this.revision,
    required this.normalizedAttributeCount,
    this.reasonCounts =
        const <NovelReaderLegacyMarkupNormalizationReason, int>{},
  });

  static const none = NovelReaderLegacyMarkupNormalizationSummary(
    revision: 0,
    normalizedAttributeCount: 0,
  );

  final int revision;
  final int normalizedAttributeCount;
  final Map<NovelReaderLegacyMarkupNormalizationReason, int> reasonCounts;

  bool get changed => normalizedAttributeCount > 0;
}

@immutable
final class NovelReaderLegacyMarkupNormalizationResult {
  const NovelReaderLegacyMarkupNormalizationResult({
    required this.html,
    required this.summary,
  });

  final String html;
  final NovelReaderLegacyMarkupNormalizationSummary summary;
}
