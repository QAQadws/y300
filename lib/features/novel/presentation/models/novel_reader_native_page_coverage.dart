import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

final class NovelReaderNativeCoveragePoint {
  const NovelReaderNativeCoveragePoint({
    required this.anchor,
    required this.fragmentIndex,
    required this.displayUtf16,
    required this.sourceRune,
    required this.affinity,
  });
  final NovelReaderTextAnchor anchor;
  final int fragmentIndex;
  final int displayUtf16;
  final int sourceRune;
  final HtmlProjectionAffinity affinity;
}

/// Pure proof for one fully checked page. A point is supported by a complete
/// visible native grapheme on its explicit side, not a min/max source interval.
/// No layouts/leases or whole chapter/page snapshots are retained.
final class NovelReaderNativePageCoverage {
  NovelReaderNativePageCoverage({
    required this.identity,
    required this.layoutId,
    required this.pageIndex,
    required Iterable<NovelReaderNativeCoveragePoint> points,
    this.hasClippedGlyphs = false,
  }) : points = List.unmodifiable(points);
  final ForumBodyIdentity identity;
  final String layoutId;
  final int pageIndex;
  final List<NovelReaderNativeCoveragePoint> points;

  /// A visible-style glyph extends outside the actual fragment/page clip.
  /// Complete native rows alone cannot prove body-end visibility in that case.
  final bool hasClippedGlyphs;

  /// Only matching format/text/episode/node/offset is exact. Endpoint plateaus
  /// choose the first downstream or last upstream point in this page. This
  /// does not confirm navigation, migrate old rows or authorize persistence.
  NovelReaderNativeCoveragePoint? locate(
    NovelReaderTextAnchor anchor, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    if (!anchor.hasCanonicalTextOffset || anchor.textOffset < 0) return null;
    NovelReaderNativeCoveragePoint? preferred;
    NovelReaderNativeCoveragePoint? fallback;
    for (final point in points) {
      final candidate = point.anchor;
      if (candidate.episodeId != anchor.episodeId ||
          candidate.nodeId != anchor.nodeId ||
          candidate.formatVersion != anchor.formatVersion ||
          candidate.textIdentity != anchor.textIdentity ||
          candidate.textOffset != anchor.textOffset) {
        continue;
      }
      if (point.affinity == affinity) {
        if (preferred == null || affinity == HtmlProjectionAffinity.upstream) {
          preferred = point;
        }
      } else if (fallback == null ||
          affinity == HtmlProjectionAffinity.upstream) {
        fallback = point;
      }
    }
    return preferred ?? fallback;
  }
}
