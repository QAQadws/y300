import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_legacy_markup_normalization.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

@immutable
class NovelReaderPaginationDiagnostics {
  NovelReaderPaginationDiagnostics({
    required this.episodeId,
    required this.paginationKey,
    required this.pageCount,
    required this.layoutDuration,
    required this.reflowCount,
    required this.unknownImageDimensionCount,
    required this.overflowPageCount,
    required this.cacheHit,
    required this.flowUnitCount,
    this.atomCount = 0,
    this.measurementCount = 0,
    this.measurementCacheHitCount = 0,
    this.measurementDuration = Duration.zero,
    this.preparationDuration = Duration.zero,
    this.atomizationDuration = Duration.zero,
    this.measureSessionCreateDuration = Duration.zero,
    this.classificationDuration = Duration.zero,
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
    this.flowableComplexAtomCount = 0,
    this.atomicWidgetAtomCount = 0,
    this.dedicatedContentAtomCount = 0,
    this.legacyMarkupNormalizerRevision = 0,
    this.normalizedLegacyAttributeCount = 0,
    this.firstPageDuration = Duration.zero,
    this.cancelledPlanCount = 0,
    this.availableHeight = 0,
    this.averageTextPageFullness = 0,
    this.lowFullnessPageCount = 0,
    Map<NovelReaderPageGapReason, int> gapReasonCounts =
        const <NovelReaderPageGapReason, int>{},
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
    Map<NovelReaderLegacyMarkupNormalizationReason, int>
        legacyMarkupNormalizationReasonCounts =
        const <NovelReaderLegacyMarkupNormalizationReason, int>{},
    List<NovelReaderPaginationMeasurementSample> measurementSamples =
        const <NovelReaderPaginationMeasurementSample>[],
  }) : gapReasonCounts = Map<NovelReaderPageGapReason, int>.unmodifiable(
         gapReasonCounts,
       ),
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
       legacyMarkupNormalizationReasonCounts =
           Map<NovelReaderLegacyMarkupNormalizationReason, int>.unmodifiable(
             legacyMarkupNormalizationReasonCounts,
           ),
       measurementSamples =
           List<NovelReaderPaginationMeasurementSample>.unmodifiable(
             measurementSamples,
           );

  final String episodeId;
  final String paginationKey;
  final int pageCount;
  final Duration layoutDuration;
  final int reflowCount;
  final int unknownImageDimensionCount;
  final int overflowPageCount;
  final bool cacheHit;
  final int flowUnitCount;
  final int atomCount;
  final int measurementCount;
  final int measurementCacheHitCount;
  final Duration measurementDuration;
  final Duration preparationDuration;
  final Duration atomizationDuration;
  final Duration measureSessionCreateDuration;
  final Duration classificationDuration;
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
  final int flowableComplexAtomCount;
  final int atomicWidgetAtomCount;
  final int dedicatedContentAtomCount;
  final int legacyMarkupNormalizerRevision;
  final int normalizedLegacyAttributeCount;
  final Duration firstPageDuration;
  final int cancelledPlanCount;
  final double availableHeight;
  final double averageTextPageFullness;
  final int lowFullnessPageCount;
  final Map<NovelReaderPageGapReason, int> gapReasonCounts;
  final Map<NovelReaderPaginationAtomKind, int> atomKindCounts;
  final Map<NovelReaderPaginationRoute, int> routeCounts;
  final Map<NovelReaderPaginationRouteReason, int> routeReasonCounts;
  final Map<NovelReaderSafeTextFallbackReason, int>
  safeTextFallbackReasonCounts;
  final Map<NovelReaderFlowableComplexFallbackReason, int>
  flowabilityFailureReasonCounts;
  final Map<NovelReaderLegacyMarkupNormalizationReason, int>
  legacyMarkupNormalizationReasonCounts;
  final List<NovelReaderPaginationMeasurementSample> measurementSamples;

  double get measurementCacheHitRate =>
      measurementCount == 0 ? 0 : measurementCacheHitCount / measurementCount;

  @override
  String toString() {
    return 'NovelReaderPaginationDiagnostics('
        'episode=$episodeId, pages=$pageCount, '
        'durationMs=${layoutDuration.inMilliseconds}, '
        'reflows=$reflowCount, unknownImageDimensions='
        '$unknownImageDimensionCount, overflowPages=$overflowPageCount, '
        'cacheHit=$cacheHit, flowUnits=$flowUnitCount, atoms=$atomCount, '
        'measurements=$measurementCount, measurementCacheHits='
        '$measurementCacheHitCount, measurementMs='
        '${measurementDuration.inMilliseconds}, averageTextFullness='
        '${averageTextPageFullness.toStringAsFixed(2)}, '
        'frameWaits=$frameWaitCount, domSlices=$domSliceCount, '
        'readableImages=$readableImageCount, '
        'prepareMs=${preparationDuration.inMilliseconds}, '
        'atomizationMs=${atomizationDuration.inMilliseconds}, '
        'sessionCreateMs=${measureSessionCreateDuration.inMilliseconds}, '
        'classificationMs=${classificationDuration.inMilliseconds}, '
        'firstPageMs=${firstPageDuration.inMilliseconds}, '
        'rendererValidations=$rendererValidationCount, '
        'rendererMismatches=$rendererValidationMismatchCount, '
        'textLayouts=$textLayoutCount, safeRuns=$safeTextRunCount, '
        'complexBlocks=$complexBlockCount, '
        'flowableComplexFragments=$flowableComplexFragmentCount, '
        'complexBoundaries=$complexBoundaryCount, '
        'complexBoundaryIndexBuilds=$complexBoundaryIndexBuildCount, '
        'complexBoundaryIndexCacheHits=$complexBoundaryIndexCacheHitCount, '
        'complexBoundaryIndexSingleFlightHits='
        '$complexBoundaryIndexSingleFlightHitCount, '
        'complexSearchProbes=$complexSearchProbeCount, '
        'complexSearchCacheHits=$complexSearchCacheHitCount, '
        'complexSearchBudgetExceeded=$complexSearchBudgetExceededCount, '
        'minimumComplexFragments=$minimumComplexFragmentCount, '
        'dedicatedImagePages=$dedicatedImagePageCount, '
        'dedicatedTablePages=$dedicatedTablePageCount, '
        'dedicatedCollapsePages=$dedicatedCollapsePageCount, '
        'atomicWidgetPages=$atomicWidgetPageCount, '
        'flowableComplexAtoms=$flowableComplexAtomCount, '
        'atomicWidgetAtoms=$atomicWidgetAtomCount, '
        'dedicatedContentAtoms=$dedicatedContentAtomCount, '
        'legacyNormalizerRevision=$legacyMarkupNormalizerRevision, '
        'normalizedLegacyAttributes=$normalizedLegacyAttributeCount, '
        'normalizationReasons=$legacyMarkupNormalizationReasonCounts, '
        'safeFallbacks=$safeTextFallbackCount, routes=$routeCounts, '
        'safeFallbackReasons=$safeTextFallbackReasonCounts, '
        'flowabilityFailures=$flowabilityFailureReasonCounts, '
        'routeReasons=$routeReasonCounts, '
        'cancelledPlans=$cancelledPlanCount, cacheHitRate='
        '${measurementCacheHitRate.toStringAsFixed(2)}, '
        'lowFullnessPages=$lowFullnessPageCount, gapReasons='
        '$gapReasonCounts, atomKinds=$atomKindCounts)';
  }
}

abstract interface class NovelReaderPaginationDiagnosticsSink {
  void record(NovelReaderPaginationDiagnostics diagnostics);
}

final class NovelReaderNoopPaginationDiagnosticsSink
    implements NovelReaderPaginationDiagnosticsSink {
  const NovelReaderNoopPaginationDiagnosticsSink();

  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) {}
}

/// Keeps pagination diagnostics available during development without emitting
/// production logs or body contents.
final class NovelReaderDebugPaginationDiagnosticsSink
    implements NovelReaderPaginationDiagnosticsSink {
  const NovelReaderDebugPaginationDiagnosticsSink();

  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) {
    if (kDebugMode) {
      debugPrint('[NovelPagination] $diagnostics');
    }
  }
}
