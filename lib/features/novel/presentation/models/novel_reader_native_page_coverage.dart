import 'dart:ui' show Rect;

import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

sealed class NovelReaderNativeCoverageLocation {
  const NovelReaderNativeCoverageLocation();
  NovelReaderTextAnchor get anchor;
  int get fragmentIndex;
  int? get displayUtf16 => null;
  int? get sourceRune => null;
  HtmlProjectionAffinity get affinity => HtmlProjectionAffinity.downstream;
}

final class NovelReaderNativeCoveragePoint
    extends NovelReaderNativeCoverageLocation {
  const NovelReaderNativeCoveragePoint({
    required this.anchor,
    required this.fragmentIndex,
    required this.displayUtf16,
    required this.sourceRune,
    required this.affinity,
  });
  @override
  final NovelReaderTextAnchor anchor;
  @override
  final int fragmentIndex;
  @override
  final int displayUtf16;
  @override
  final int sourceRune;
  @override
  final HtmlProjectionAffinity affinity;
}

/// Proof of the actual visible resource frame, not of loaded pixels or text.
/// Images own no text/source range; the parent's insertion fence only orders
/// them among text points and cannot prove a resource's semantic position.
final class NovelReaderNativeImageCoverage
    extends NovelReaderNativeCoverageLocation {
  const NovelReaderNativeImageCoverage({
    required this.anchor,
    required this.fragmentIndex,
    required this.path,
    required this.imageIndex,
    required this.rect,
    this.inlineAtomIndex,
    this.parentDisplayFenceUtf16,
  });
  @override
  final NovelReaderTextAnchor anchor;
  @override
  final int fragmentIndex;
  final String path;
  final int imageIndex;
  final Rect rect;
  final int? inlineAtomIndex;

  /// The actual parent's empty insertion fence, used only to merge reading
  /// order. This is not image text coverage, a source cursor or a saved anchor.
  final int? parentDisplayFenceUtf16;
}

/// Pure geometry proof for one fully checked page. Text points require a
/// complete visible native grapheme; images require their actual resource
/// rectangle. Loaded pixels are checked separately on the mounted fragment.
/// No layouts/leases or whole chapter/page snapshots are retained.
final class NovelReaderNativePageCoverage {
  NovelReaderNativePageCoverage({
    required this.identity,
    required this.layoutId,
    required this.pageIndex,
    required Iterable<NovelReaderNativeCoveragePoint> points,
    this.hasClippedGlyphs = false,
    Iterable<NovelReaderNativeImageCoverage> images = const [],
    this.hasClippedResources = false,
  }) : points = List.unmodifiable(points),
       images = List.unmodifiable(images);
  final ForumBodyIdentity identity;
  final String layoutId;
  final int pageIndex;
  final List<NovelReaderNativeCoveragePoint> points;
  final List<NovelReaderNativeImageCoverage> images;
  final bool hasClippedResources;
  int get locationCount => points.length + images.length;
  bool get hasLocations => points.isNotEmpty || images.isNotEmpty;

  /// Both source walks are already ordered by actual fragment index. Merge
  /// without sorting/copying an entire page or treating an image as a glyph.
  Iterable<NovelReaderNativeCoverageLocation> get locations sync* {
    var text = 0, image = 0;
    while (text < points.length || image < images.length) {
      if (image == images.length ||
          (text < points.length &&
              _textBeforeImage(points[text], images[image]))) {
        yield points[text++];
      } else {
        yield images[image++];
      }
    }
  }

  static bool _textBeforeImage(
    NovelReaderNativeCoveragePoint point,
    NovelReaderNativeImageCoverage image,
  ) {
    if (point.fragmentIndex != image.fragmentIndex) {
      return point.fragmentIndex < image.fragmentIndex;
    }
    final fence = image.parentDisplayFenceUtf16;
    return fence == null ||
        point.displayUtf16 < fence ||
        (point.displayUtf16 == fence &&
            point.affinity == HtmlProjectionAffinity.upstream);
  }

  /// A visible-style glyph extends outside the actual fragment/page clip.
  /// Complete native rows alone cannot prove body-end visibility in that case.
  final bool hasClippedGlyphs;

  /// Only matching format/text/episode/node/offset is exact. Endpoint plateaus
  /// choose the first downstream or last upstream point in this page. This
  /// does not confirm navigation, migrate old rows or authorize persistence.
  NovelReaderNativeCoverageLocation? locate(
    NovelReaderTextAnchor anchor, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    if (!anchor.hasCanonicalTextOffset || anchor.textOffset < 0) return null;
    NovelReaderNativeCoverageLocation? preferred;
    NovelReaderNativeCoverageLocation? fallback;
    for (final point in locations) {
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
