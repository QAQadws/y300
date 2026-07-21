import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_text_run.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_text_pagination.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_block_pagination_engine.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_incremental_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_page_composer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_text_run_extractor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_text_pagination_engine.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

abstract interface class NovelReaderHybridPaginationPlanner {
  Future<NovelReaderPaginationPlan> plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}

final class DefaultNovelReaderHybridPaginationPlanner
    implements
        NovelReaderHybridPaginationPlanner,
        NovelReaderIncrementalPaginationPlanner,
        NovelReaderPageBreaker,
        NovelReaderIsolatedPageBreakerFactory,
        NovelReaderCancellablePageBreaker {
  DefaultNovelReaderHybridPaginationPlanner({
    required NovelReaderPaginationMeasureAdapter measureAdapter,
    required this.preferences,
    required this.theme,
    required this.baseStyle,
    this.textDirection = TextDirection.ltr,
    this.textAlign = TextAlign.start,
    this.textScaler = TextScaler.noScaling,
    this.atomExtractor = const NovelReaderPaginationAtomExtractor(),
    this.atomClassifier = const NovelReaderPaginationAtomClassifier(),
    this.textRunExtractor = const NovelReaderPaginationTextRunExtractor(),
    this.complexBlockEngine = const NovelReaderComplexBlockPaginationEngine(),
    this.validationPolicy = const NovelReaderPaginationValidationPolicy(),
    NovelReaderPaginationMeasureSessionFactory? measureSessionFactory,
    NovelReaderPaginationMeasureCache? measureCache,
    NovelReaderTextMetricsCache? textMetricsCache,
    this.measureCacheCapacity = 512,
    this.maxPages = 5000,
  }) : _measureAdapter = measureAdapter,
       _measureSessionFactory =
           measureSessionFactory ??
           (measureAdapter is NovelReaderPaginationMeasureSessionFactory
               ? measureAdapter as NovelReaderPaginationMeasureSessionFactory
               : NovelReaderAdapterMeasureSessionFactory(measureAdapter)),
       measureCache =
           measureCache ??
           NovelReaderPaginationMeasureCache(capacity: measureCacheCapacity),
       textMetricsCache = textMetricsCache ?? NovelReaderTextMetricsCache();

  final NovelReaderPaginationMeasureAdapter _measureAdapter;
  final NovelReaderPaginationMeasureSessionFactory _measureSessionFactory;
  final ForumHtmlReaderPreferences preferences;
  final ForumHtmlThemeContext theme;
  final TextStyle baseStyle;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final TextScaler textScaler;
  final NovelReaderPaginationAtomExtractor atomExtractor;
  final NovelReaderPaginationAtomClassifier atomClassifier;
  final NovelReaderPaginationTextRunExtractor textRunExtractor;
  final NovelReaderComplexBlockPaginationEngine complexBlockEngine;
  final NovelReaderPaginationValidationPolicy validationPolicy;
  final NovelReaderPaginationMeasureCache measureCache;
  final NovelReaderTextMetricsCache textMetricsCache;
  final int measureCacheCapacity;
  final int maxPages;

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) {
    return plan(
      chapter: chapter,
      key: key,
      cancellationToken: NovelReaderPaginationCancellationToken(),
    );
  }

  @override
  Future<NovelReaderPaginationPlan> paginateCancellable(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
    NovelReaderPaginationCancellationToken cancellationToken,
  ) {
    return plan(
      chapter: chapter,
      key: key,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<NovelReaderPaginationPlan> plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) {
    return _plan(
      chapter: chapter,
      key: key,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<NovelReaderPaginationProgress> planIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) {
    late final StreamController<NovelReaderPaginationProgress> controller;
    controller = StreamController<NovelReaderPaginationProgress>(
      onListen: () {
        unawaited(
          _plan(
            chapter: chapter,
            key: key,
            cancellationToken: cancellationToken,
            onProgress: (progress) async {
              if (!controller.isClosed) {
                controller.add(progress);
                await Future<void>.delayed(Duration.zero);
              }
            },
          ).then<void>(
            (_) async {
              if (!controller.isClosed) {
                await controller.close();
              }
            },
            onError: (Object error, StackTrace stackTrace) async {
              if (!controller.isClosed) {
                controller.addError(error, stackTrace);
                await controller.close();
              }
            },
          ),
        );
      },
      onCancel: cancellationToken.cancel,
    );
    return controller.stream;
  }

  Future<NovelReaderPaginationPlan> _plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationCancellationToken cancellationToken,
    Future<void> Function(NovelReaderPaginationProgress progress)? onProgress,
  }) async {
    _validateInput(chapter, key);
    cancellationToken.throwIfCancelled();

    final atomizationStopwatch = Stopwatch()..start();
    final atoms = atomExtractor.extract(chapter);
    atomizationStopwatch.stop();
    final classificationStopwatch = Stopwatch()..start();
    final classifiedAtoms = atoms
        .map(
          (atom) => atomClassifier.classify(
            atom: atom,
            baseStyle: baseStyle,
            preferences: preferences,
            theme: theme,
          ),
        )
        .toList(growable: false);
    classificationStopwatch.stop();

    final atomKinds = <NovelReaderPaginationAtomKind, int>{};
    final routes = <NovelReaderPaginationRoute, int>{};
    final routeReasons = <NovelReaderPaginationRouteReason, int>{};
    final atomKindById = <String, NovelReaderPaginationAtomKind>{};
    for (final classified in classifiedAtoms) {
      atomKinds.update(
        classified.atom.kind,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      routes.update(classified.route, (value) => value + 1, ifAbsent: () => 1);
      routeReasons.update(
        classified.reason,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      atomKindById[classified.atom.atomId] = classified.atom.kind;
    }

    final sessionStopwatch = Stopwatch()..start();
    final session = _TrackedPaginationMeasureSession(
      delegate: NovelReaderCachingPaginationMeasureSession(
        delegate: _measureSessionFactory.create(chapter: chapter, key: key),
        cache: measureCache,
      ),
      atomKinds: atomKindById,
    );
    sessionStopwatch.stop();
    final validator = NovelReaderSessionPaginationRendererValidator(session);
    final complexMeasurer = NovelReaderSessionComplexBlockMeasurer(session);
    final textEngine = DefaultNovelReaderTextPaginationEngine(
      metricsCache: textMetricsCache,
    );
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: key.viewportHeightPx.toDouble(),
      maxPages: maxPages,
    );

    var textLayoutCount = 0;
    var textFastPathCount = 0;
    var safeTextRunCount = 0;
    var complexBlockCount = 0;
    var safeTextFallbackCount = 0;
    var rendererValidationCount = 0;
    var rendererValidationMismatchCount = 0;
    var domSliceCount = 0;
    var safePageOrdinal = 0;
    final safeTextFallbackReasonCounts =
        <NovelReaderSafeTextFallbackReason, int>{};
    final validatedRiskStyleSignatures = <String>{};
    var processedAtomCount = 0;
    var publishedPageCount = 0;

    NovelReaderPaginationPlan snapshotPlan(
      List<NovelReaderPageFragment> pages,
    ) {
      return NovelReaderPaginationPlan(
        key: key,
        episodeId: chapter.episodeId,
        pages: pages,
        atomCount: atoms.length,
        measurementCount: session.measurementCount,
        measurementCacheHitCount: session.cacheHitCount,
        measurementDuration: session.measurementDuration,
        atomizationDuration: atomizationStopwatch.elapsed,
        measureSessionCreateDuration: sessionStopwatch.elapsed,
        classificationDuration: classificationStopwatch.elapsed,
        frameWaitCount: session.frameWaitCount,
        domSliceCount: domSliceCount,
        readableImageCount: chapter.renderDocument.sequence.entries.length,
        textFastPathCount: textFastPathCount,
        safeTextRunCount: safeTextRunCount,
        rendererValidationCount: rendererValidationCount,
        rendererValidationMismatchCount: rendererValidationMismatchCount,
        textLayoutCount: textLayoutCount,
        complexBlockCount: complexBlockCount,
        safeTextFallbackCount: safeTextFallbackCount,
        atomKindCounts: atomKinds,
        routeCounts: routes,
        routeReasonCounts: routeReasons,
        safeTextFallbackReasonCounts: safeTextFallbackReasonCounts,
        measurementSamples: session.samples,
      );
    }

    Future<void> publishFinalPages({bool isComplete = false}) async {
      if (onProgress == null) {
        return;
      }
      cancellationToken.throwIfCancelled();
      final pages = composer.pages;
      if (!isComplete && pages.length <= publishedPageCount) {
        return;
      }
      publishedPageCount = pages.length;
      await onProgress(
        NovelReaderPaginationProgress(
          plan: snapshotPlan(pages),
          isComplete: isComplete,
          processedAtomCount: processedAtomCount,
          totalAtomCount: atoms.length,
        ),
      );
    }

    Future<void> fallbackWholeSafeAtom(
      NovelReaderClassifiedPaginationAtom classified,
      NovelReaderSafeTextFallbackReason reason,
    ) async {
      safeTextFallbackCount += 1;
      safeTextFallbackReasonCounts.update(
        reason,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      complexBlockCount += 1;
      final fallback = _complexFallbackForAtom(classified);
      final block = await complexBlockEngine.paginate(
        atom: fallback,
        chapter: chapter,
        key: key,
        measurer: complexMeasurer,
      );
      composer.appendComplexBlock(fallback, block);
      processedAtomCount += 1;
      await publishFinalPages();
    }

    try {
      for (
        var classifiedIndex = 0;
        classifiedIndex < classifiedAtoms.length;
        classifiedIndex += 1
      ) {
        final classified = classifiedAtoms[classifiedIndex];
        cancellationToken.throwIfCancelled();
        switch (classified.route) {
          case NovelReaderPaginationRoute.safeText:
            late final List<NovelReaderPaginationTextRun> runs;
            try {
              runs = textRunExtractor.extract(
                classifiedAtom: classified,
                baseStyle: baseStyle,
                preferences: preferences,
                theme: theme,
              );
            } catch (error) {
              if (_isCancellation(error)) {
                rethrow;
              }
              await fallbackWholeSafeAtom(
                classified,
                NovelReaderSafeTextFallbackReason.textRunExtractionFailure,
              );
              continue;
            }
            safeTextRunCount += runs.length;
            if (composer.hasBufferedContent &&
                composer.remainingHeight < _minimumLineHeight(runs)) {
              composer.flush(
                gapReason: NovelReaderPageGapReason.algorithmBoundary,
              );
            }
            late NovelReaderTextPaginationResult textResult;
            try {
              textResult = textEngine.paginate(
                atom: classified,
                runs: runs,
                width: key.viewportWidthPx.toDouble(),
                pageHeight: key.viewportHeightPx.toDouble(),
                firstPageHeight: composer.remainingHeight,
                paragraphSpacing: preferences.typography.paragraphSpacing,
                typographySignature: key.typographySignature,
                textDirection: textDirection,
                textAlign: textAlign,
                textScaler: textScaler,
              );
              textLayoutCount += textResult.layoutCount;
              domSliceCount += textResult.chunks.length;
              if (composer.hasBufferedContent &&
                  textResult.chunks.isNotEmpty &&
                  textResult.chunks.first.isOversized) {
                composer.flush(
                  gapReason: NovelReaderPageGapReason.algorithmBoundary,
                );
                textResult = textEngine.paginate(
                  atom: classified,
                  runs: runs,
                  width: key.viewportWidthPx.toDouble(),
                  pageHeight: key.viewportHeightPx.toDouble(),
                  paragraphSpacing: preferences.typography.paragraphSpacing,
                  typographySignature: key.typographySignature,
                  textDirection: textDirection,
                  textAlign: textAlign,
                  textScaler: textScaler,
                );
                textLayoutCount += textResult.layoutCount;
                domSliceCount += textResult.chunks.length;
              }
            } catch (error) {
              if (_isCancellation(error)) {
                rethrow;
              }
              await fallbackWholeSafeAtom(
                classified,
                NovelReaderSafeTextFallbackReason.textLayoutFailure,
              );
              continue;
            }

            final nextAtomIsBodyText =
                classifiedIndex + 1 < classifiedAtoms.length &&
                classifiedAtoms[classifiedIndex + 1].route ==
                    NovelReaderPaginationRoute.safeText &&
                classifiedAtoms[classifiedIndex + 1].atom.kind !=
                    NovelReaderPaginationAtomKind.heading;
            if (classified.atom.kind == NovelReaderPaginationAtomKind.heading &&
                nextAtomIsBodyText &&
                composer.hasBufferedContent &&
                textResult.chunks.isNotEmpty &&
                textResult.chunks.first.usedHeight + _baseLineHeight() >
                    composer.remainingHeight) {
              composer.flush(
                gapReason: NovelReaderPageGapReason.algorithmBoundary,
              );
            }

            final riskStyleSignature = _riskStyleSignature(runs);
            final needsRiskStyleValidation =
                riskStyleSignature != null &&
                !validatedRiskStyleSignatures.contains(riskStyleSignature);
            late final _TextValidationSummary validation;
            try {
              validation = await _validateTextChunk(
                chunks: textResult.chunks,
                chunkIndex: 0,
                classified: classified,
                hasRiskStyle: needsRiskStyleValidation,
                chapter: chapter,
                key: key,
                validator: validator,
                composer: composer,
                safePageOrdinal: safePageOrdinal,
                cancellationToken: cancellationToken,
              );
            } catch (error) {
              if (_isCancellation(error)) {
                rethrow;
              }
              rendererValidationCount += 1;
              await fallbackWholeSafeAtom(
                classified,
                NovelReaderSafeTextFallbackReason.rendererValidationFailure,
              );
              continue;
            }
            rendererValidationCount += validation.validationCount;
            rendererValidationMismatchCount += validation.mismatchCount;
            var accepted = textResult;
            var keepBackedChunksSeparate = false;
            var firstChunkValidated = validation.validationCount > 0;
            if (firstChunkValidated && validation.firstMismatch == null) {
              if (riskStyleSignature != null) {
                validatedRiskStyleSignatures.add(riskStyleSignature);
              }
            }
            if (validation.firstMismatch != null) {
              if (composer.hasBufferedContent) {
                composer.flush(
                  gapReason: NovelReaderPageGapReason.algorithmBoundary,
                );
              }
              final ratio =
                  (key.viewportHeightPx /
                          validation.firstMismatch!.actualHeight)
                      .clamp(0.5, 0.95);
              final backedHeight = key.viewportHeightPx * ratio;
              late final NovelReaderTextPaginationResult backed;
              try {
                backed = textEngine.paginate(
                  atom: classified,
                  runs: runs,
                  width: key.viewportWidthPx.toDouble(),
                  pageHeight: backedHeight,
                  firstPageHeight: backedHeight,
                  paragraphSpacing: preferences.typography.paragraphSpacing,
                  typographySignature: key.typographySignature,
                  textDirection: textDirection,
                  textAlign: textAlign,
                  textScaler: textScaler,
                );
              } catch (error) {
                if (_isCancellation(error)) {
                  rethrow;
                }
                await fallbackWholeSafeAtom(
                  classified,
                  NovelReaderSafeTextFallbackReason.textLayoutFailure,
                );
                continue;
              }
              textLayoutCount += backed.layoutCount;
              domSliceCount += backed.chunks.length;
              late final NovelReaderRendererValidationResult backedValidation;
              try {
                backedValidation = await validator.validate(
                  html: backed.chunks.first.html,
                  atomId: classified.atom.atomId,
                  chapter: chapter,
                  key: key,
                  availableHeight: key.viewportHeightPx.toDouble(),
                );
              } catch (error) {
                if (_isCancellation(error)) {
                  rethrow;
                }
                rendererValidationCount += 1;
                await fallbackWholeSafeAtom(
                  classified,
                  NovelReaderSafeTextFallbackReason.rendererValidationFailure,
                );
                continue;
              }
              rendererValidationCount += 1;
              if (!backedValidation.matches) {
                rendererValidationMismatchCount += 1;
                await fallbackWholeSafeAtom(
                  classified,
                  NovelReaderSafeTextFallbackReason.rendererMismatch,
                );
                continue;
              }
              accepted = backed;
              keepBackedChunksSeparate = true;
              firstChunkValidated = true;
              if (riskStyleSignature != null) {
                validatedRiskStyleSignatures.add(riskStyleSignature);
              }
            }
            var remainderFellBack = false;
            for (var index = 0; index < accepted.chunks.length; index += 1) {
              final chunk = accepted.chunks[index];
              final shouldValidate =
                  !(index == 0 && firstChunkValidated) &&
                  validationPolicy.shouldValidate(
                    safePageOrdinal: safePageOrdinal,
                    hasRiskStyle: false,
                  );
              if (shouldValidate) {
                cancellationToken.throwIfCancelled();
                NovelReaderRendererValidationResult result;
                var validationFailed = false;
                try {
                  result = await validator.validate(
                    html: composer.hasBufferedContent
                        ? '${composer.bufferedHtml}${chunk.html}'
                        : chunk.html,
                    atomId: classified.atom.atomId,
                    chapter: chapter,
                    key: key,
                    availableHeight: key.viewportHeightPx.toDouble(),
                  );
                } catch (error) {
                  if (_isCancellation(error)) {
                    rethrow;
                  }
                  validationFailed = true;
                  result = NovelReaderRendererValidationResult(
                    actualHeight: double.infinity,
                    availableHeight: key.viewportHeightPx.toDouble(),
                    measurementCacheHit: false,
                    frameWaitCount: 0,
                  );
                }
                rendererValidationCount += 1;
                if (!result.matches) {
                  rendererValidationMismatchCount += 1;
                  safeTextFallbackCount += 1;
                  safeTextFallbackReasonCounts.update(
                    validationFailed
                        ? NovelReaderSafeTextFallbackReason
                              .rendererValidationFailure
                        : NovelReaderSafeTextFallbackReason.rendererMismatch,
                    (value) => value + 1,
                    ifAbsent: () => 1,
                  );
                  complexBlockCount += 1;
                  composer.flush(
                    gapReason: NovelReaderPageGapReason.algorithmBoundary,
                  );
                  final fallback = _complexFallbackForRemainder(
                    classified: classified,
                    chunks: accepted.chunks,
                    startIndex: index,
                  );
                  final block = await complexBlockEngine.paginate(
                    atom: fallback,
                    chapter: chapter,
                    key: key,
                    measurer: complexMeasurer,
                  );
                  composer.appendComplexBlock(fallback, block);
                  await publishFinalPages();
                  remainderFellBack = true;
                  break;
                }
              }
              composer.appendTextChunk(chunk);
              if (keepBackedChunksSeparate) {
                composer.flush(
                  gapReason: NovelReaderPageGapReason.algorithmBoundary,
                );
              }
              textFastPathCount += 1;
              safePageOrdinal += 1;
              await publishFinalPages();
            }
            if (remainderFellBack) {
              await publishFinalPages();
            }
          case NovelReaderPaginationRoute.isolatedImage:
            late final NovelReaderPaginationMeasureResult measured;
            try {
              measured = await session.measure(
                NovelReaderPaginationMeasureRequest(
                  html: classified.atom.html,
                  chapter: chapter,
                  key: key,
                  atomId: classified.atom.atomId,
                  startOffset: 0,
                  endOffset: classified.atom.textLength,
                ),
              );
            } on NovelReaderPaginationException catch (error) {
              if (error.code != 'measurementTimeout') {
                rethrow;
              }
              measured = NovelReaderPaginationMeasureResult(
                height: key.viewportHeightPx + 1.0,
              );
            }
            composer.appendIsolatedImage(
              atom: classified,
              measuredHeight: measured.height,
            );
            await publishFinalPages();
          case NovelReaderPaginationRoute.rubyInline:
          case NovelReaderPaginationRoute.collapseBlock:
          case NovelReaderPaginationRoute.tableBlock:
          case NovelReaderPaginationRoute.complexHtml:
            complexBlockCount += 1;
            final block = await complexBlockEngine.paginate(
              atom: classified,
              chapter: chapter,
              key: key,
              measurer: complexMeasurer,
            );
            var combineWithBufferedContent = false;
            if (composer.canAppendComplexBlock(block)) {
              cancellationToken.throwIfCancelled();
              try {
                final validation = await validator.validate(
                  html: '${composer.bufferedHtml}${block.html}',
                  atomId: '${classified.atom.atomId}:composition',
                  chapter: chapter,
                  key: key,
                  availableHeight: key.viewportHeightPx.toDouble(),
                );
                rendererValidationCount += 1;
                combineWithBufferedContent = validation.matches;
                if (!validation.matches) {
                  rendererValidationMismatchCount += 1;
                }
              } catch (error) {
                if (_isCancellation(error)) {
                  rethrow;
                }
                rendererValidationCount += 1;
              }
            }
            composer.appendComplexBlock(
              classified,
              block,
              combineWithBufferedContent: combineWithBufferedContent,
            );
            await publishFinalPages();
        }
        processedAtomCount += 1;
        await publishFinalPages();
      }
      cancellationToken.throwIfCancelled();
      final pages = composer.finish();
      final plan = snapshotPlan(pages);
      await publishFinalPages(isComplete: true);
      return plan;
    } finally {
      await session.dispose();
    }
  }

  Future<_TextValidationSummary> _validateTextChunk({
    required List<NovelReaderTextPageChunk> chunks,
    required int chunkIndex,
    required NovelReaderClassifiedPaginationAtom classified,
    required bool hasRiskStyle,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationRendererValidator validator,
    required NovelReaderPaginationPageComposer composer,
    required int safePageOrdinal,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) async {
    if (chunkIndex < 0 || chunkIndex >= chunks.length) {
      return const _TextValidationSummary(
        validationCount: 0,
        mismatchCount: 0,
        firstMismatch: null,
      );
    }
    if (!validationPolicy.shouldValidate(
      safePageOrdinal: safePageOrdinal,
      hasRiskStyle: hasRiskStyle,
    )) {
      return const _TextValidationSummary(
        validationCount: 0,
        mismatchCount: 0,
        firstMismatch: null,
      );
    }
    cancellationToken.throwIfCancelled();
    final html = composer.hasBufferedContent
        ? '${composer.bufferedHtml}${chunks[chunkIndex].html}'
        : chunks[chunkIndex].html;
    final result = await validator.validate(
      html: html,
      atomId: classified.atom.atomId,
      chapter: chapter,
      key: key,
      availableHeight: key.viewportHeightPx.toDouble(),
    );
    return _TextValidationSummary(
      validationCount: 1,
      mismatchCount: result.matches ? 0 : 1,
      firstMismatch: result.matches ? null : result,
    );
  }

  NovelReaderClassifiedPaginationAtom _complexFallbackForRemainder({
    required NovelReaderClassifiedPaginationAtom classified,
    required List<NovelReaderTextPageChunk> chunks,
    required int startIndex,
  }) {
    final first = chunks[startIndex];
    final html = chunks.skip(startIndex).map((chunk) => chunk.html).join();
    final atom = classified.atom;
    return NovelReaderClassifiedPaginationAtom(
      atom: NovelReaderPaginationAtom(
        atomId: '${atom.atomId}:fallback-${first.sourceStart}',
        kind: atom.kind,
        html: html,
        startAnchor: first.startAnchor,
        endAnchor: atom.endAnchor,
        textLength: atom.textLength - first.sourceStart,
        imageIndices: atom.imageIndices,
        breakability: atom.breakability,
        imagePagePolicy: atom.imagePagePolicy,
      ),
      route: NovelReaderPaginationRoute.complexHtml,
      isBreakable: false,
      reason: NovelReaderPaginationRouteReason.unsupportedStyle,
    );
  }

  NovelReaderClassifiedPaginationAtom _complexFallbackForAtom(
    NovelReaderClassifiedPaginationAtom classified,
  ) {
    return NovelReaderClassifiedPaginationAtom(
      atom: classified.atom,
      route: NovelReaderPaginationRoute.complexHtml,
      isBreakable: false,
      reason: NovelReaderPaginationRouteReason.unsupportedStyle,
    );
  }

  bool _isCancellation(Object error) {
    return error is NovelReaderPaginationException &&
        error.code == 'paginationCancelled';
  }

  double _minimumLineHeight(List<NovelReaderPaginationTextRun> runs) {
    var minimum = double.infinity;
    for (final run in runs) {
      if (run.isParagraphBreak) {
        continue;
      }
      final fontSize = run.style.fontSize ?? baseStyle.fontSize ?? 14;
      final height = run.style.height ?? baseStyle.height ?? 1.2;
      minimum = minimum < fontSize * height ? minimum : fontSize * height;
    }
    return minimum.isFinite ? minimum : 1;
  }

  double _baseLineHeight() {
    final fontSize = baseStyle.fontSize ?? 14;
    final height = baseStyle.height ?? 1.2;
    return fontSize * height;
  }

  String? _riskStyleSignature(List<NovelReaderPaginationTextRun> runs) {
    final signatures = <String>{};
    for (final run in runs) {
      final style = run.style;
      if (_isRiskStyle(style)) {
        signatures.add(
          jsonEncode(<Object?>[
            style.backgroundColor?.toARGB32(),
            style.fontFamily,
            style.fontSize,
            style.height,
            style.fontWeight?.value,
            style.fontStyle?.index,
          ]),
        );
      }
    }
    if (signatures.isEmpty) {
      return null;
    }
    final ordered = signatures.toList(growable: false)..sort();
    return ordered.join('|');
  }

  bool _isRiskStyle(TextStyle style) {
    return style.backgroundColor != null ||
        style.fontFamily != baseStyle.fontFamily ||
        style.fontSize != baseStyle.fontSize ||
        style.fontWeight != baseStyle.fontWeight ||
        style.fontStyle != baseStyle.fontStyle;
  }

  void _validateInput(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) {
    if (chapter.episodeId != key.episodeId) {
      throw const NovelReaderPaginationException(
        code: 'episodeMismatch',
        message:
            'Prepared chapter and pagination key refer to different episodes.',
      );
    }
    if (key.viewportWidthPx <= 0 ||
        key.viewportHeightPx <= 0 ||
        maxPages <= 0 ||
        measureCacheCapacity <= 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidBudget',
        message: 'Hybrid pagination requires positive viewport and budgets.',
      );
    }
  }

  @override
  NovelReaderPageBreaker createIsolated() {
    return DefaultNovelReaderHybridPaginationPlanner(
      measureAdapter: _measureAdapter,
      preferences: preferences,
      theme: theme,
      baseStyle: baseStyle,
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
      atomExtractor: atomExtractor,
      atomClassifier: atomClassifier,
      textRunExtractor: textRunExtractor,
      complexBlockEngine: complexBlockEngine,
      validationPolicy: validationPolicy,
      measureSessionFactory: _measureSessionFactory,
      measureCache: measureCache,
      textMetricsCache: textMetricsCache,
      measureCacheCapacity: measureCacheCapacity,
      maxPages: maxPages,
    );
  }
}

final class _TextValidationSummary {
  const _TextValidationSummary({
    required this.validationCount,
    required this.mismatchCount,
    required this.firstMismatch,
  });

  final int validationCount;
  final int mismatchCount;
  final NovelReaderRendererValidationResult? firstMismatch;
}

final class _TrackedPaginationMeasureSession
    implements NovelReaderPaginationMeasureSession {
  _TrackedPaginationMeasureSession({
    required NovelReaderPaginationMeasureSession delegate,
    required this.atomKinds,
  }) : _delegate = delegate;

  final NovelReaderPaginationMeasureSession _delegate;
  final Map<String, NovelReaderPaginationAtomKind> atomKinds;
  int measurementCount = 0;
  int cacheHitCount = 0;
  int frameWaitCount = 0;
  Duration measurementDuration = Duration.zero;
  final List<NovelReaderPaginationMeasurementSample> samples =
      <NovelReaderPaginationMeasurementSample>[];

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    measurementCount += 1;
    final stopwatch = Stopwatch()..start();
    final result = await _delegate.measure(request);
    stopwatch.stop();
    measurementDuration += stopwatch.elapsed;
    frameWaitCount += result.frameWaitCount;
    if (result.fromCache) {
      cacheHitCount += 1;
    }
    if (samples.length < 64) {
      final rawAtomId = request.atomId?.replaceFirst(':validation', '') ?? '';
      samples.add(
        NovelReaderPaginationMeasurementSample(
          atomId: request.atomId ?? '',
          atomKind:
              atomKinds[rawAtomId] ??
              NovelReaderPaginationAtomKind.atomicWidget,
          height: result.height,
          duration: stopwatch.elapsed,
          fromCache: result.fromCache,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> dispose() => _delegate.dispose();
}
