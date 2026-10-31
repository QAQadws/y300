import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

import 'novel_reader_source_anchor_projection.dart';

/// A verified source span, not a claim that its text is actually rendered.
final class NovelReaderNativeAnchorSegment {
  const NovelReaderNativeAnchorSegment({
    required this.sourceStart,
    required this.projection,
  });
  final int sourceStart;
  final NovelReaderSourceAnchorProjection projection;
  int get sourceEnd => sourceStart + projection.sourceRuneLength;
}

final class NovelReaderNativeAnchorPosition {
  const NovelReaderNativeAnchorPosition({
    required this.anchor,
    required this.sourceRune,
    required this.displayUtf16,
    required this.isExact,
  });
  final NovelReaderTextAnchor anchor;
  final int sourceRune;
  final int displayUtf16;

  /// A snapped grapheme/source discontinuity remains an approximate hint.
  /// This flag alone does not prove page coverage or authorize persistence.
  final bool isExact;
}

/// Pure per-document mapping. Native layouts/leases, DOM, semantic documents,
/// callbacks and reading owners are not retained. Maps never write positions.
final class NovelReaderNativeAnchorMap {
  NovelReaderNativeAnchorMap({
    required this.identity,
    required this.episodeId,
    required this.sourceRuneLength,
    required Iterable<NovelReaderNativeAnchorSegment> segments,
    required Iterable<String> unmappedPaths,
  }) : segments = List.unmodifiable(segments),
       unmappedPaths = List.unmodifiable(unmappedPaths) {
    if (sourceRuneLength < 0) throw ArgumentError.value(sourceRuneLength);
    var end = 0;
    for (final segment in this.segments) {
      if (segment.sourceStart < end ||
          segment.sourceEnd <= segment.sourceStart ||
          segment.sourceEnd > sourceRuneLength ||
          segment.projection.baseAnchor.episodeId != episodeId ||
          !segment.projection.baseAnchor.hasCanonicalTextOffset) {
        throw ArgumentError('Invalid native anchor segments');
      }
      end = segment.sourceEnd;
    }
  }

  final ForumBodyIdentity identity;
  final String episodeId;
  final int sourceRuneLength;
  final List<NovelReaderNativeAnchorSegment> segments;
  final List<String> unmappedPaths;

  /// Source lookup needs explicit affinity at the shared end/start of two
  /// origins. A gap is never clamped to a nearby semantic node.
  NovelReaderTextAnchor? anchorAtSourceRune(
    int sourceRune, {
    required HtmlProjectionAffinity affinity,
    bool requireAdjacentOrigin = false,
  }) {
    RangeError.checkValueInInterval(
      sourceRune,
      0,
      sourceRuneLength,
      'sourceRune',
    );
    var low = 0;
    var high = segments.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (segments[middle].sourceStart < sourceRune) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final after =
        low < segments.length && segments[low].sourceStart == sourceRune
        ? segments[low]
        : null;
    final before = low > 0 && sourceRune <= segments[low - 1].sourceEnd
        ? segments[low - 1]
        : null;
    final segment = affinity == HtmlProjectionAffinity.downstream
        ? after ?? before
        : before ?? after;
    // Coverage must have a known origin on the glyph's actual side. A point
    // lookup may use the opposite side at an endpoint; that is insufficient
    // proof when its adjacent glyph belongs to an unmapped origin.
    if (requireAdjacentOrigin &&
        segment != null &&
        (affinity == HtmlProjectionAffinity.downstream
            ? sourceRune >= segment.sourceEnd
            : sourceRune <= segment.sourceStart)) {
      return null;
    }
    return segment?.projection.anchorAtSourceRune(
      sourceRune - segment.sourceStart,
    );
  }

  /// Projects through the actual paragraph's display-to-source map. This is a
  /// candidate point; the caller must separately verify its visible line range.
  NovelReaderNativeAnchorPosition? projectDisplayPosition({
    required ForumBodyParagraphContent content,
    required int displayUtf16,
    required HtmlProjectionAffinity affinity,
  }) {
    if (content.identity != identity) {
      throw StateError('Native anchor content identity changed');
    }
    final source = content.projection.sourceAtUtf16(
      displayUtf16,
      affinity: affinity,
    );
    final anchor = anchorAtSourceRune(source.sourceRune, affinity: affinity);
    return anchor == null
        ? null
        : NovelReaderNativeAnchorPosition(
            anchor: anchor,
            sourceRune: source.sourceRune,
            displayUtf16: source.displayUtf16,
            isExact: source.isExact,
          );
  }
}
