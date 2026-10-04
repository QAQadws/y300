import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';

enum NovelReaderSafeTextFallbackReason {
  textRunExtractionFailure,
  textLayoutFailure,
  rendererValidationFailure,
  rendererMismatch,
}

@immutable
class NovelReaderPaginationMeasurementSample {
  const NovelReaderPaginationMeasurementSample({
    required this.atomId,
    required this.atomKind,
    required this.height,
    required this.duration,
    this.fromCache = false,
    this.htmlCodeUnits = 0,
  });

  final String atomId;
  final NovelReaderPaginationAtomKind atomKind;
  final double height;
  final Duration duration;
  final bool fromCache;
  final int htmlCodeUnits;
}

@immutable
class NovelReaderPaginationPlan {
  NovelReaderPaginationPlan({
    required this.key,
    required this.episodeId,
    required List<NovelReaderPageFragment> pages,
    this.atomCount = 0,
    this.measurementCount = 0,
    this.measurementCacheHitCount = 0,
    this.measurementDuration = Duration.zero,
    this.atomizationDuration = Duration.zero,
    this.measureSessionCreateDuration = Duration.zero,
    this.classificationDuration = Duration.zero,
    this.longestSynchronousStepDuration = Duration.zero,
    this.maximumCandidateHtmlCodeUnits = 0,
    this.totalCandidateHtmlCodeUnits = 0,
    this.uncachedCandidateHtmlCodeUnits = 0,
    this.frameWaitCount = 0,
    this.domSliceCount = 0,
    this.readableImageCount = 0,
    this.textFastPathCount = 0,
    this.safeTextRunCount = 0,
    this.rendererValidationCount = 0,
    this.rendererValidationMismatchCount = 0,
    this.textLayoutCount = 0,
    this.complexBlockCount = 0,
    this.flowableComplexFragmentCount = 0,
    this.complexBoundaryCount = 0,
    this.complexBoundaryIndexBuildCount = 0,
    this.complexBoundaryIndexBuildDuration = Duration.zero,
    this.complexBoundaryIndexCacheHitCount = 0,
    this.complexBoundaryIndexSingleFlightHitCount = 0,
    this.complexSearchProbeCount = 0,
    this.complexSearchCacheHitCount = 0,
    this.complexSearchBudgetExceededCount = 0,
    this.minimumComplexFragmentCount = 0,
    this.dedicatedImagePageCount = 0,
    this.dedicatedTablePageCount = 0,
    this.dedicatedCollapsePageCount = 0,
    this.atomicWidgetPageCount = 0,
    this.safeTextFallbackCount = 0,
    Map<NovelReaderPaginationAtomKind, int> atomKindCounts =
        const <NovelReaderPaginationAtomKind, int>{},
    Map<NovelReaderPaginationRoute, int> routeCounts =
        const <NovelReaderPaginationRoute, int>{},
    Map<NovelReaderPaginationRouteReason, int> routeReasonCounts =
        const <NovelReaderPaginationRouteReason, int>{},
    Map<NovelReaderSafeTextFallbackReason, int> safeTextFallbackReasonCounts =
        const <NovelReaderSafeTextFallbackReason, int>{},
    Map<NovelReaderFlowableComplexFallbackReason, int>
        flowabilityFailureReasonCounts =
        const <NovelReaderFlowableComplexFallbackReason, int>{},
    List<NovelReaderPaginationMeasurementSample> measurementSamples =
        const <NovelReaderPaginationMeasurementSample>[],
  }) : pages = List<NovelReaderPageFragment>.unmodifiable(pages),
       atomKindCounts = Map<NovelReaderPaginationAtomKind, int>.unmodifiable(
         atomKindCounts,
       ),
       routeCounts = Map<NovelReaderPaginationRoute, int>.unmodifiable(
         routeCounts,
       ),
       routeReasonCounts =
           Map<NovelReaderPaginationRouteReason, int>.unmodifiable(
             routeReasonCounts,
           ),
       safeTextFallbackReasonCounts =
           Map<NovelReaderSafeTextFallbackReason, int>.unmodifiable(
             safeTextFallbackReasonCounts,
           ),
       flowabilityFailureReasonCounts =
           Map<NovelReaderFlowableComplexFallbackReason, int>.unmodifiable(
             flowabilityFailureReasonCounts,
           ),
       measurementSamples =
           List<NovelReaderPaginationMeasurementSample>.unmodifiable(
             measurementSamples,
           );

  final NovelReaderPaginationKey key;
  final String episodeId;
  final List<NovelReaderPageFragment> pages;
  final int atomCount;
  final int measurementCount;
  final int measurementCacheHitCount;
  final Duration measurementDuration;
  final Duration atomizationDuration;
  final Duration measureSessionCreateDuration;
  final Duration classificationDuration;

  /// Maximum observed classification/run/TextPainter/index step, not a frame
  /// stall or a complete trace of every synchronous operation.
  final Duration longestSynchronousStepDuration;

  /// HTML UTF-16 cost proxies; totals include cached and failed attempts.
  final int maximumCandidateHtmlCodeUnits;
  final int totalCandidateHtmlCodeUnits;

  /// Successful measurements confirmed not to have come from cache.
  final int uncachedCandidateHtmlCodeUnits;
  final int frameWaitCount;
  final int domSliceCount;
  final int readableImageCount;
  final int textFastPathCount;
  final int safeTextRunCount;
  final int rendererValidationCount;
  final int rendererValidationMismatchCount;
  final int textLayoutCount;
  final int complexBlockCount;
  final int flowableComplexFragmentCount;
  final int complexBoundaryCount;
  final int complexBoundaryIndexBuildCount;
  final Duration complexBoundaryIndexBuildDuration;
  final int complexBoundaryIndexCacheHitCount;
  final int complexBoundaryIndexSingleFlightHitCount;
  final int complexSearchProbeCount;
  final int complexSearchCacheHitCount;
  final int complexSearchBudgetExceededCount;
  final int minimumComplexFragmentCount;
  final int dedicatedImagePageCount;
  final int dedicatedTablePageCount;
  final int dedicatedCollapsePageCount;
  final int atomicWidgetPageCount;
  final int safeTextFallbackCount;
  final Map<NovelReaderPaginationAtomKind, int> atomKindCounts;
  final Map<NovelReaderPaginationRoute, int> routeCounts;
  final Map<NovelReaderPaginationRouteReason, int> routeReasonCounts;
  final Map<NovelReaderSafeTextFallbackReason, int>
  safeTextFallbackReasonCounts;
  final Map<NovelReaderFlowableComplexFallbackReason, int>
  flowabilityFailureReasonCounts;
  final List<NovelReaderPaginationMeasurementSample> measurementSamples;

  int get pageCount => pages.length;

  int get flowableComplexAtomCount =>
      routeCounts[NovelReaderPaginationRoute.flowableComplexText] ?? 0;

  int get atomicWidgetAtomCount =>
      routeCounts[NovelReaderPaginationRoute.atomicWidget] ?? 0;

  int get dedicatedContentAtomCount =>
      (routeCounts[NovelReaderPaginationRoute.isolatedImage] ?? 0) +
      (routeCounts[NovelReaderPaginationRoute.tableBlock] ?? 0) +
      (routeCounts[NovelReaderPaginationRoute.collapseBlock] ?? 0);

  bool get hasOverflowFallback => pages.any((page) => page.hasOverflow);

  double get averageTextPageFullness {
    final values = pages
        .where(
          (page) => !page.isDedicatedContentPage && page.availableHeight > 0,
        )
        .map((page) => page.fullness)
        .toList(growable: false);
    if (values.isEmpty) {
      return 0;
    }
    return values.reduce((left, right) => left + right) / values.length;
  }

  int get lowFullnessPageCount => pages
      .where(
        (page) =>
            !page.containsIsolatedImage &&
            !page.isDedicatedContentPage &&
            page.availableHeight > 0 &&
            page.fullness < 0.65,
      )
      .length;

  Map<NovelReaderPageGapReason, int> get gapReasonCounts {
    final counts = <NovelReaderPageGapReason, int>{};
    for (final page in pages) {
      counts.update(page.gapReason, (value) => value + 1, ifAbsent: () => 1);
    }
    return Map<NovelReaderPageGapReason, int>.unmodifiable(counts);
  }

  NovelReaderPageFragment? pageAt(int index) {
    if (index < 0 || index >= pages.length) {
      return null;
    }
    return pages[index];
  }

  int? pageIndexForAnchor(
    NovelReaderTextAnchor anchor, {
    required bool isPlanComplete,
  }) {
    if (anchor.episodeId != episodeId || !anchor.hasCanonicalTextOffset) {
      return null;
    }
    for (final page in pages) {
      final ranges = page.anchorRanges.isEmpty
          ? <NovelReaderPageAnchorRange>[
              NovelReaderPageAnchorRange(
                start: page.startAnchor,
                end: page.endAnchor,
              ),
            ]
          : page.anchorRanges;
      for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
        final range = ranges[rangeIndex];
        if (_contains(
          range.start,
          range.end,
          anchor,
          includesTerminalEnd:
              isPlanComplete &&
              page.index == pages.length - 1 &&
              rangeIndex == ranges.length - 1,
        )) {
          return page.index;
        }
      }
    }
    return null;
  }

  /// Legacy and incompatible anchors can locate a node, but their numeric
  /// offsets cannot be interpreted as canonical code points.
  int? pageIndexForNode(NovelReaderTextAnchor anchor) {
    if (anchor.episodeId != episodeId || anchor.nodeId == null) return null;
    for (final page in pages) {
      if (page.anchorRanges.isEmpty) {
        if (page.startAnchor.nodeId == anchor.nodeId ||
            page.endAnchor.nodeId == anchor.nodeId) {
          return page.index;
        }
      } else {
        for (final range in page.anchorRanges) {
          if (range.start.nodeId == anchor.nodeId ||
              range.end.nodeId == anchor.nodeId) {
            return page.index;
          }
        }
      }
    }
    return null;
  }

  bool hasMatchingTextIdentity(NovelReaderTextAnchor anchor) {
    if (anchor.episodeId != episodeId || !anchor.hasCanonicalTextOffset) {
      return false;
    }
    for (final page in pages) {
      if (page.anchorRanges.isEmpty) {
        if (_sameText(page.startAnchor, anchor) &&
            _sameText(page.endAnchor, anchor)) {
          return true;
        }
      } else {
        for (final range in page.anchorRanges) {
          if (_sameText(range.start, anchor) && _sameText(range.end, anchor)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _contains(
    NovelReaderTextAnchor start,
    NovelReaderTextAnchor end,
    NovelReaderTextAnchor target, {
    required bool includesTerminalEnd,
  }) {
    if (!_sameText(start, target) || !_sameText(end, target)) {
      return false;
    }
    final startOffset = start.textOffset;
    final endOffset = end.textOffset;
    if (startOffset < 0 || endOffset < startOffset) return false;
    if (startOffset == endOffset) {
      return target.textOffset == startOffset;
    }
    return target.textOffset >= startOffset &&
        (target.textOffset < endOffset ||
            (includesTerminalEnd && target.textOffset == endOffset));
  }

  bool _sameText(NovelReaderTextAnchor left, NovelReaderTextAnchor right) =>
      left.hasCanonicalTextOffset &&
      left.episodeId == right.episodeId &&
      left.nodeId == right.nodeId &&
      left.textIdentity == right.textIdentity;
}
