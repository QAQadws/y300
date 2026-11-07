import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

import 'novel_reader_source_anchor_projection.dart';

/// Inclusive raw source boundary candidates for one verified semantic point.
/// A plateau can cover collapsed whitespace. It is not visible-page coverage.
final class NovelReaderNativeSourceCandidate {
  const NovelReaderNativeSourceCandidate(this.runeStart, this.runeEnd);
  final int runeStart;
  final int runeEnd;
}

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

/// Qualified resource slot, separate from every text coordinate system.
/// The empty layout-only anchor binds the exact whole converted input.
final class NovelReaderNativeImageAnchor {
  const NovelReaderNativeImageAnchor({
    required this.path,
    required this.anchor,
    required this.rawSource,
    required this.url,
    required this.imageIndex,
  });
  final String path, rawSource, url;
  final int imageIndex;
  final NovelReaderTextAnchor anchor;
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
    Iterable<NovelReaderNativeImageAnchor> images = const [],
  }) : segments = List.unmodifiable(segments),
       images = List.unmodifiable(images),
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
      final anchor = segment.projection.baseAnchor;
      (_byAnchor[(anchor.nodeId, anchor.formatVersion, anchor.textIdentity)] ??=
              [])
          .add(segment);
    }
    for (final image in this.images) {
      final anchor = image.anchor;
      final key = (anchor.nodeId, anchor.formatVersion, anchor.textIdentity);
      if (image.path.isEmpty ||
          image.rawSource.isEmpty ||
          image.url.isEmpty ||
          image.imageIndex < 0 ||
          anchor.episodeId != episodeId ||
          !anchor.hasCanonicalTextOffset ||
          anchor.textOffset != 0 ||
          _imagesByPath.containsKey(image.path) ||
          _imagesByAnchor.containsKey(key) ||
          _byAnchor.containsKey(key)) {
        throw ArgumentError('Invalid native image anchors');
      }
      _imagesByPath[image.path] = image;
      _imagesByAnchor[key] = image;
    }
  }

  final ForumBodyIdentity identity;
  final String episodeId;
  final int sourceRuneLength;
  final List<NovelReaderNativeAnchorSegment> segments;
  final List<String> unmappedPaths;
  final List<NovelReaderNativeImageAnchor> images;
  final _imagesByPath = <String, NovelReaderNativeImageAnchor>{};
  final _imagesByAnchor =
      <(String?, int, String?), NovelReaderNativeImageAnchor>{};
  final _byAnchor =
      <(String?, int, String?), List<NovelReaderNativeAnchorSegment>>{};

  bool hasVerifiedTextIdentity(NovelReaderTextAnchor anchor) =>
      anchor.hasCanonicalTextOffset &&
      anchor.nodeId != null &&
      anchor.episodeId == episodeId &&
      (_byAnchor.containsKey((
            anchor.nodeId,
            anchor.formatVersion,
            anchor.textIdentity,
          )) ||
          _imagesByAnchor.containsKey((
            anchor.nodeId,
            anchor.formatVersion,
            anchor.textIdentity,
          )));

  /// Inverts a complete semantic interval against this document's verified
  /// origins. No raw source interval crosses a missing semantic segment.
  List<ForumBodySourceRange> sourceRanges(NovelReaderTextRange range) {
    final anchor = range.start;
    final end = range.endTextOffset;
    if (anchor.episodeId != episodeId ||
        !anchor.hasCanonicalTextOffset ||
        anchor.textOffset < 0 ||
        anchor.textOffset >= end) {
      return const [];
    }
    final matching =
        _byAnchor[(anchor.nodeId, anchor.formatVersion, anchor.textIdentity)];
    if (matching == null) return const [];
    final ranges = <ForumBodySourceRange>[];
    var offset = anchor.textOffset;
    for (final segment in matching) {
      final boundaries = segment.projection.semanticOffsetsBySourceRuneBoundary;
      if (boundaries.last <= offset) continue;
      if (boundaries.first > offset) return const [];
      final stop = end < boundaries.last ? end : boundaries.last;
      final from = _semanticBoundary(boundaries, offset, after: true) - 1;
      final to = _semanticBoundary(boundaries, stop, after: false);
      if (boundaries[from] != offset || boundaries[to] != stop) return const [];
      var rawStart = segment.sourceStart + from;
      if (ranges.lastOrNull?.endRune == rawStart) {
        rawStart = ranges.removeLast().startRune;
      }
      ranges.add(
        ForumBodySourceRange(identity, rawStart, segment.sourceStart + to),
      );
      offset = stop;
      if (offset == end) return List.unmodifiable(ranges);
    }
    return const [];
  }

  NovelReaderNativeImageAnchor? imageAtPath(String path) => _imagesByPath[path];

  /// Resource hints always use exact recorded paths. No zero-length numeric
  /// interval, equal URL or neighboring text can identify an image.
  Iterable<String> imageCandidatePaths(
    NovelReaderTextAnchor anchor, {
    bool allowNodeCompatibility = false,
  }) sync* {
    if (anchor.episodeId != episodeId || anchor.nodeId == null) return;
    final image =
        _imagesByAnchor[(
          anchor.nodeId,
          anchor.formatVersion,
          anchor.textIdentity,
        )];
    if (image != null) {
      if (anchor.hasCanonicalTextOffset && anchor.textOffset == 0) {
        yield image.path;
      }
    } else if (allowNodeCompatibility) {
      for (final image in images) {
        if (image.anchor.nodeId == anchor.nodeId) yield image.path;
      }
    }
  }

  /// Inverts only proven origin projections. Binary lookup retains whole
  /// matching plateaus; equal shared endpoints merge, raw source gaps do not.
  /// Default lookup never substitutes an old/mismatched identity. Explicit
  /// node compatibility returns hints for read-only recovery, never exact proof.
  Iterable<NovelReaderNativeSourceCandidate> sourceCandidates(
    NovelReaderTextAnchor anchor, {
    bool allowNodeCompatibility = false,
  }) sync* {
    if (anchor.episodeId != episodeId || anchor.nodeId == null) {
      return;
    }
    final matching =
        _byAnchor[(anchor.nodeId, anchor.formatVersion, anchor.textIdentity)];
    if (matching == null) {
      // Explicit read-only compatibility search by the recorded node ID only.
      // A known canonical identity with a pending/bad offset never uses this.
      if (allowNodeCompatibility) {
        for (final segment in segments) {
          if (segment.projection.baseAnchor.nodeId == anchor.nodeId) {
            yield NovelReaderNativeSourceCandidate(
              segment.sourceStart,
              segment.sourceEnd,
            );
          }
        }
      }
      return;
    }
    if (!anchor.hasCanonicalTextOffset || anchor.textOffset < 0) return;
    NovelReaderNativeSourceCandidate? pending;
    for (final segment in matching) {
      final values = segment.projection.semanticOffsetsBySourceRuneBoundary;
      final first = _semanticBoundary(values, anchor.textOffset, after: false);
      if (first == values.length || values[first] != anchor.textOffset) {
        continue;
      }
      final last =
          _semanticBoundary(values, anchor.textOffset, after: true) - 1;
      final start = segment.sourceStart + first;
      final end = segment.sourceStart + last;
      if (pending != null && start <= pending.runeEnd) {
        pending = NovelReaderNativeSourceCandidate(pending.runeStart, end);
      } else {
        if (pending != null) yield pending;
        pending = NovelReaderNativeSourceCandidate(start, end);
      }
    }
    if (pending != null) yield pending;
  }

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

int _semanticBoundary(List<int> values, int offset, {required bool after}) {
  var low = 0;
  var high = values.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (values[middle] < offset || (after && values[middle] == offset)) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}
