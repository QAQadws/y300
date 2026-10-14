import 'package:flutter/foundation.dart';

enum ForumHtmlSafeDisplayPlanKind { whole, textLines, paragraphs }

enum ForumHtmlSafeDisplayFallbackReason {
  belowThreshold,
  unsupportedStructure,
  noSafeBoundaries,
  oversizedChunk,
}

/// Session-neutral display values, never DOM, layout, or canonical coordinates.
@immutable
final class ForumHtmlSafeDisplayPlan {
  ForumHtmlSafeDisplayPlan({
    required this.sourceHtml,
    required this.sourceId,
    required this.kind,
    required List<ForumHtmlDisplayChunk> chunks,
    this.fallbackReason,
  }) : chunks = List<ForumHtmlDisplayChunk>.unmodifiable(chunks);

  final String sourceHtml;
  final String sourceId;
  final ForumHtmlSafeDisplayPlanKind kind;
  final List<ForumHtmlDisplayChunk> chunks;
  final ForumHtmlSafeDisplayFallbackReason? fallbackReason;

  bool get isChunked => kind != ForumHtmlSafeDisplayPlanKind.whole;

  /// Hard lines for textLines, top-level P blocks for paragraphs; whole is opaque.
  int get unitCount => chunks.isEmpty ? 0 : chunks.last.endUnit;

  ForumHtmlDisplayChunk? chunkForUnit(int unit) {
    if (unit < 0 || unit >= unitCount) return null;
    var low = 0;
    var high = chunks.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final chunk = chunks[middle];
      if (unit < chunk.startUnit) {
        high = middle;
      } else if (unit >= chunk.endUnit) {
        low = middle + 1;
      } else {
        return chunk;
      }
    }
    return null;
  }
}

/// The sourceId remains the logical body owner; layoutIdentity keys this part.
@immutable
final class ForumHtmlDisplayChunk {
  const ForumHtmlDisplayChunk({
    required this.ordinal,
    required this.html,
    required this.hasTrailingContent,
    required this.sourceId,
    required this.sourceHtml,
    required this.startUnit,
    required this.endUnit,
  });

  final int ordinal;
  final String html;
  final bool hasTrailingContent;
  final String sourceId;
  final String sourceHtml;

  /// Inclusive/exclusive source-neutral units, independent of chunk grouping.
  /// These are display units, not persisted anchors or text offsets.
  final int startUnit;
  final int endUnit;

  Object get layoutIdentity => (sourceId, sourceHtml, ordinal, html);
}
