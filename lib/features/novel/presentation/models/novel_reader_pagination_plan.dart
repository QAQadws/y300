import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';

@immutable
class NovelReaderPaginationMeasurementSample {
  const NovelReaderPaginationMeasurementSample({
    required this.atomId,
    required this.atomKind,
    required this.height,
    required this.duration,
    this.fromCache = false,
  });

  final String atomId;
  final NovelReaderPaginationAtomKind atomKind;
  final double height;
  final Duration duration;
  final bool fromCache;
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
    this.frameWaitCount = 0,
    this.domSliceCount = 0,
    this.readableImageCount = 0,
    this.textFastPathCount = 0,
    this.rendererValidationCount = 0,
    this.rendererValidationMismatchCount = 0,
    this.textLayoutCount = 0,
    this.complexBlockCount = 0,
    this.safeTextFallbackCount = 0,
    Map<NovelReaderPaginationAtomKind, int> atomKindCounts =
        const <NovelReaderPaginationAtomKind, int>{},
    Map<NovelReaderPaginationRoute, int> routeCounts =
        const <NovelReaderPaginationRoute, int>{},
    Map<NovelReaderPaginationRouteReason, int> routeReasonCounts =
        const <NovelReaderPaginationRouteReason, int>{},
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
  final int frameWaitCount;
  final int domSliceCount;
  final int readableImageCount;
  final int textFastPathCount;
  final int rendererValidationCount;
  final int rendererValidationMismatchCount;
  final int textLayoutCount;
  final int complexBlockCount;
  final int safeTextFallbackCount;
  final Map<NovelReaderPaginationAtomKind, int> atomKindCounts;
  final Map<NovelReaderPaginationRoute, int> routeCounts;
  final Map<NovelReaderPaginationRouteReason, int> routeReasonCounts;
  final List<NovelReaderPaginationMeasurementSample> measurementSamples;

  int get pageCount => pages.length;

  bool get hasOverflowFallback => pages.any((page) => page.hasOverflow);

  double get averageTextPageFullness {
    final values = pages
        .where(
          (page) => !page.containsIsolatedImage && page.availableHeight > 0,
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

  int? pageIndexForAnchor(NovelReaderTextAnchor anchor) {
    if (anchor.episodeId != episodeId) {
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
      for (final range in ranges) {
        if (_contains(
          range.start,
          range.end,
          anchor,
          isLastPage: page.index == pages.length - 1,
        )) {
          return page.index;
        }
      }
    }
    return null;
  }

  bool _contains(
    NovelReaderTextAnchor start,
    NovelReaderTextAnchor end,
    NovelReaderTextAnchor target, {
    required bool isLastPage,
  }) {
    if (start.nodeId != target.nodeId || end.nodeId != target.nodeId) {
      return false;
    }
    final startOffset = start.textOffset;
    final endOffset = end.textOffset < startOffset
        ? startOffset
        : end.textOffset;
    if (startOffset == endOffset) {
      return target.textOffset == startOffset;
    }
    return target.textOffset >= startOffset &&
        (target.textOffset < endOffset || isLastPage);
  }
}
