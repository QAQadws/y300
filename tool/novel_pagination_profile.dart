// Isolated profile target: production pagination, synthetic content, no DB or network.
// Run with --profile and a separate Android application ID; never replace user data.
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/l10n/app_localizations.dart';

final _errors = <String>[];
const _profilePartialNavigation = bool.fromEnvironment(
  'PROFILE_PARTIAL_NAVIGATION',
  defaultValue: true,
);

/// Read the mounted, currently turnable prefix without production diagnostics.
@visibleForTesting
int? visiblePaginationPageCount(BuildContext context) {
  int? count;
  var found = false;
  void visit(Element element) {
    if (found) return;
    final widget = element.widget;
    if (widget is PageView &&
        widget.key == const Key('novel-reader-paged-page-view')) {
      found = true;
      count = widget.childrenDelegate.estimatedChildCount;
      return;
    }
    element.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  return count;
}

/// An invalid interaction window must not become a successful background test.
@visibleForTesting
String? partialNavigationInvalidReason({
  required bool firstReadableWasPartial,
  required bool completed,
  required Iterable<
    ({bool pending, bool uncovered, bool accepted, bool covered, bool reached})
  >
  requests,
}) {
  final observations = requests.toList(growable: false);
  if (!firstReadableWasPartial) return 'completed_before_first_input';
  if (observations.isEmpty) return 'no_navigation_requests';
  if (!observations.any((request) => request.pending && request.uncovered)) {
    return 'no_pending_uncovered_request';
  }
  if (observations.any(
    (request) => !request.accepted || !request.covered || !request.reached,
  )) {
    return 'navigation_target_not_reached';
  }
  if (!completed) return 'pagination_not_completed';
  return null;
}

/// Keep interaction metadata separate from the already dense plan record.
@visibleForTesting
Map<String, Object?> navigationProfileSummary({
  required String name,
  required String? invalidReason,
  required bool firstReadableWasPartial,
  required int requestsWhilePending,
  required int uncoveredRequestsWhilePending,
  required int? interactionWindowUs,
}) => {
  'event': 'scenario_navigation_summary',
  'name': name,
  'valid': invalidReason == null,
  'invalidReason': invalidReason,
  'firstReadableWasPartial': firstReadableWasPartial,
  'requestsWhilePending': requestsWhilePending,
  'uncoveredRequestsWhilePending': uncoveredRequestsWhilePending,
  'referencePagesAt450x800': 9,
  'interactionWindowUs': interactionWindowUs,
  'coverageSource': 'mounted-page-view',
  'coveragePollMs': 20,
};

void _emit(Map<String, Object?> value) {
  // ignore: avoid_print
  print('NOVEL_PROFILE ${jsonEncode(value)}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  void record(Object error) {
    _errors.add(error.runtimeType.toString());
    _emit({'event': 'runtime_error', 'type': error.runtimeType.toString()});
  }

  FlutterError.onError = (details) => record(details.exception);
  PlatformDispatcher.instance.onError = (error, stack) {
    record(error);
    return true;
  };
  runApp(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: ThemeData.light(),
        home: const _ProfileReader(),
      ),
    ),
  );
}

class _ProfileReader extends StatefulWidget {
  const _ProfileReader();
  @override
  State<_ProfileReader> createState() => _ProfileReaderState();
}

class _ProfileReaderState extends State<_ProfileReader> {
  final _plans = NovelReaderPaginationCache();
  final _measures = NovelReaderPaginationMeasureCache();
  final _boundaries = NovelReaderComplexHtmlBoundaryCache();
  final _prepared = NovelReaderPreparedChapterCache();
  final _navigation = NovelReaderPagedNavigationController();
  final _results = <Map<String, Object?>>[];
  final _runs = <_Run>[];
  final _frames = <FrameTiming>[];
  _Run? _run;
  String _html = '';
  int _generation = 0;
  bool _visible = false;
  NovelReaderPageSeekRequest? _seek;
  late NovelReaderProgressSnapshot _snapshot;
  late NovelReaderDocument _document;
  NovelReaderPreferences _preferences = NovelReaderPreferences.defaults()
      .copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
        fontSize: 18.5,
        lineHeight: 1.6,
        paragraphSpacing: 12,
        conversionMode: NovelReaderConversionMode.none,
      );

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_suite()));
  }

  void _timings(List<FrameTiming> frames) {
    _frames.addAll(frames);
  }

  void _clearCaches() {
    _plans.clear();
    _measures.clear();
    _boundaries.clear();
    _prepared.clear();
  }

  Future<void> _suite() async {
    // Android can deliver the first framework frame before its view metrics.
    // Start comparable layout clocks only after a real viewport is available.
    for (var attempt = 0; attempt < 250; attempt++) {
      if (!mounted) {
        return;
      }
      if (!View.of(context).physicalSize.isEmpty &&
          !MediaQuery.sizeOf(context).isEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted) {
      return;
    }
    if (View.of(context).physicalSize.isEmpty ||
        MediaQuery.sizeOf(context).isEmpty) {
      _emit({
        'event': 'suite_done',
        'suitePassed': false,
        'error': 'no_viewport',
      });
      return;
    }
    final view = View.of(context);
    _emit({
      'event': 'suite_start',
      'revision': const String.fromEnvironment(
        'PROFILE_REVISION',
        defaultValue: 'unlabelled',
      ),
      'deviceLabel': const String.fromEnvironment(
        'PROFILE_DEVICE',
        defaultValue: 'unlabelled',
      ),
      'profileMode': kProfileMode,
      'physicalSize': [view.physicalSize.width, view.physicalSize.height],
      'devicePixelRatio': view.devicePixelRatio,
      'logicalViewport': [
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height,
      ],
      'textScaleAtOne': MediaQuery.textScalerOf(context).scale(1),
      'fontFamily': _preferences.fontFamily,
      'syntheticContent': true,
      'partialNavigationRequested': _profilePartialNavigation,
    });
    try {
      await _scenario('safe-cold', _safeHtml, clear: true);
      await _scenario('complex-cold', _complexHtml, clear: true);
      final warm = await _scenario(
        'complex-warm',
        _complexHtml,
        action: (run) async {
          final position = run.position!;
          final middle = position.pageCount ~/ 2;
          setState(
            () => _seek = NovelReaderPageSeekRequest(
              requestId: _generation,
              episodeId: position.episodeId,
              paginationKey: position.paginationKey,
              pageIndex: middle,
            ),
          );
          await _wait(() => run.position?.pageIndex == middle);
        },
      );
      final middle = warm.position == null ? null : _saved(warm.position!);
      if (middle != null) {
        await _scenario(
          'middle-restore',
          _complexHtml,
          clear: true,
          snapshot: middle,
        );
      }
      final turned = await _scenario(
        'rapid-turn',
        _complexHtml,
        action: (run) async {
          for (var index = 0; index < 8; index++) {
            final before = run.position!.pageIndex;
            await _wait(_navigation.turnNext);
            await _wait(() => run.position!.pageIndex == before + 1);
          }
        },
      );
      await _scenario(
        'typography-reflow',
        _complexHtml,
        fontSize: 22,
        keepSurface: true,
        maximumAnchorBacktrack: (turned.lastPageSpan ?? 0) * 2,
        snapshot: turned.position == null ? middle : _saved(turned.position!),
      );
      final retired = _start(
        'chapter-retirement',
        _complexHtml + _complexHtml,
        clear: true,
      );
      await WidgetsBinding.instance.endOfFrame;
      retired.pendingAtRetirement = !retired.complete;
      _finish(retired, retired: true);
      await _scenario('chapter-switch', _safeHtml, keepSurface: true);
      final exited = _start(
        'exit-late',
        _complexHtml + _complexHtml,
        clear: true,
      );
      await WidgetsBinding.instance.endOfFrame;
      exited.pendingAtRetirement = !exited.complete;
      setState(() => _visible = false);
      await WidgetsBinding.instance.endOfFrame;
      _finish(exited, retired: true);
      _clearCaches();
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (_profilePartialNavigation) {
        await _partialNavigationScenario();
      }
      // Leave known, completed production content for screenshots/manual turns.
      await _scenario('safe-final-visible', _safeHtml);
    } catch (error) {
      _errors.add('suite_${error.runtimeType}');
    } finally {
      // Timing reports arrive in batches. Attribute by raster wall time only
      // after the final flush; receiving a report does not identify its scene.
      await Future<void>.delayed(const Duration(seconds: 1));
      for (final run in _runs) {
        _report(run);
      }
      _emit({
        'event': 'suite_done',
        'suitePassed':
            _errors.isEmpty &&
            _results.every((result) => result['passed'] == true),
        'scenarios': _results.length,
        'runtimeErrors': _errors,
      });
    }
  }

  _Run _start(
    String name,
    String html, {
    bool clear = false,
    NovelReaderProgressSnapshot? snapshot,
    double fontSize = 18.5,
    bool keepSurface = false,
  }) {
    if (clear) {
      _clearCaches();
    }
    final episodeId = name.startsWith('safe-') || name == 'chapter-switch'
        ? 'profile-safe'
        : 'profile-complex';
    final run = _Run(name, episodeId);
    _runs.add(run);
    _document = const DiscuzNovelReaderDocumentParser().parse(
      episodeId: episodeId,
      rawHtml: html,
      fallbackParagraphs: const [],
    );
    setState(() {
      _run = run;
      _html = html;
      if (!keepSurface) {
        _generation++;
      }
      _seek = null;
      _visible = true;
      _preferences = _preferences.copyWith(fontSize: fontSize);
      _snapshot =
          snapshot ??
          const NovelReaderProgressPolicy().initialSnapshot(
            novelId: 'profile-novel',
            episodeId: episodeId,
            flowMode: _preferences.flowMode,
          );
    });
    _emit({
      'event': 'begin',
      'scenario': name,
      'htmlCodeUnits': html.length,
      'fontSize': fontSize,
      'restore': snapshot != null,
    });
    return run;
  }

  Future<_Run> _scenario(
    String name,
    String html, {
    bool clear = false,
    NovelReaderProgressSnapshot? snapshot,
    double fontSize = 18.5,
    int? maximumAnchorBacktrack,
    bool keepSurface = false,
    Future<void> Function(_Run)? action,
  }) async {
    final run = _start(
      name,
      html,
      clear: clear,
      snapshot: snapshot,
      fontSize: fontSize,
      keepSurface: keepSurface,
    );
    try {
      await _wait(
        () => run.readyUs != null && run.complete && run.position != null,
      );
      if (action != null) {
        await action(run);
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (snapshot != null &&
          name == 'middle-restore' &&
          run.position?.pageIndex != snapshot.pageIndex) {
        run.errors.add('restored_page_mismatch');
      }
      final diagnostic = run.records.last;
      if (name.endsWith('-cold') && diagnostic.cacheHit) {
        run.errors.add('cold_plan_unexpected_cache_hit');
      }
      if (name == 'complex-warm' && !diagnostic.cacheHit) {
        run.errors.add('warm_plan_cache_miss');
      }
      if (snapshot != null &&
          (name == 'middle-restore' || name == 'typography-reflow') &&
          (run.position!.isReadOnlyCompatibilityRestore ||
              run.position!.anchor.formatVersion !=
                  snapshot.anchorFormatVersion ||
              run.position!.anchor.textIdentity !=
                  snapshot.anchorTextIdentity)) {
        run.errors.add('canonical_restore_not_confirmed');
      }
      if (snapshot != null && name == 'typography-reflow') {
        final position = run.position!;
        final backtrack =
            snapshot.anchorTextOffset - position.anchor.textOffset;
        // Font enlargement may move the page start backwards. Compare the
        // actual previous page span, rather than inventing a Unicode capacity.
        if (position.paginationKey == snapshot.paginationKey ||
            position.anchor.nodeId != snapshot.anchorNodeId ||
            position.anchor.textOffset <= 0 ||
            backtrack < 0 ||
            maximumAnchorBacktrack == null ||
            backtrack > maximumAnchorBacktrack) {
          run.errors.add('reflow_anchor_not_preserved');
        }
      }
    } catch (error) {
      run.errors.add('scenario_${error.runtimeType}');
    }
    _finish(run);
    return run;
  }

  Future<void> _wait(bool Function() condition) async {
    final clock = Stopwatch()..start();
    while (true) {
      if (mounted && _run?.partialNavigation == true) {
        _observeVisibleCoverage(_run!);
      }
      if (condition()) return;
      if (!mounted || _errors.isNotEmpty || _run!.errors.isNotEmpty) {
        throw StateError('Profile work failed.');
      }
      if (clock.elapsed > const Duration(seconds: 30)) {
        throw TimeoutException('Bounded profile operation did not finish.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void _observeVisibleCoverage(_Run run) {
    if (!mounted || !_visible || !identical(_run, run)) return;
    final count = visiblePaginationPageCount(context);
    run.availablePages = count;
    run.observePageRequests(visiblePageCount: count);
  }

  Future<void> _partialNavigationScenario() async {
    final run = _start('complex-partial-navigation', _complexHtml, clear: true);
    run.partialNavigation = true;
    try {
      // Wake directly from the real ready/position callbacks, rather than
      // polling until a fast device has already finished the remaining pages.
      await run.readable.future.timeout(const Duration(seconds: 30));
      run.firstReadableWasPartial =
          !run.complete && !run.position!.isPageCountFinal;
      run.interactionWallStart = DateTime.now().microsecondsSinceEpoch;
      if (run.firstReadableWasPartial) {
        for (var index = 0; index < 3; index++) {
          final position = run.position!;
          _observeVisibleCoverage(run);
          final availablePages = run.availablePages;
          if (availablePages == null) {
            throw StateError('The readable page view is not mounted.');
          }
          final request = _PageRequest(
            from: position.pageIndex,
            target: position.pageIndex + 1,
            requestedUs: run.clock.elapsedMicroseconds,
            availablePages: availablePages,
            pending: !run.complete && !position.isPageCountFinal,
          );
          run.pageRequests.add(request);
          run.observePageRequests();
          // The old surface rejects an uncovered edge. The new surface may
          // accept a pending turn, so stop submitting once it accepts this one.
          await _wait(() {
            if (_navigation.turnNext()) {
              request.acceptedUs = run.clock.elapsedMicroseconds;
              return true;
            }
            request.rejectedAttempts++;
            return false;
          });
          await _wait(() => request.reachedUs != null);
        }
      }
      run.interactionWallEnd = DateTime.now().microsecondsSinceEpoch;
      await _wait(() => run.complete && run.position?.isPageCountFinal == true);
      if (run.records.last.cacheHit) {
        run.errors.add('partial_navigation_unexpected_plan_cache_hit');
      }
      if (run.pageRequests.isNotEmpty &&
          (run.position!.pageIndex != run.pageRequests.last.target ||
              run.records.last.pageCount <= run.pageRequests.last.target)) {
        run.errors.add('partial_navigation_final_coverage_mismatch');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (error) {
      run.errors.add('partial_navigation_${error.runtimeType}');
    }
    run.interactionWallEnd ??= DateTime.now().microsecondsSinceEpoch;
    run.partialNavigationInvalidReason = partialNavigationInvalidReason(
      firstReadableWasPartial: run.firstReadableWasPartial,
      completed: run.complete,
      requests: run.pageRequests.map(
        (request) => (
          pending: request.pending,
          uncovered: request.uncovered,
          accepted: request.acceptedUs != null,
          covered: request.coveredUs != null,
          reached: request.reachedUs != null,
        ),
      ),
    );
    _finish(run);
  }

  NovelReaderProgressSnapshot _saved(NovelReaderPaginationPosition position) =>
      NovelReaderProgressSnapshot(
        novelId: 'profile-novel',
        episodeId: position.episodeId,
        flowMode: _preferences.flowMode,
        scrollOffset: 0,
        pageIndex: position.pageIndex,
        pageCount: position.pageCount,
        anchorNodeId: position.anchor.nodeId,
        anchorTextOffset: position.anchor.textOffset,
        paginationKey: position.paginationKey,
        anchorFormatVersion: position.anchor.formatVersion,
        anchorTextIdentity: position.anchor.textIdentity,
        progressPercent: 0,
        isProgressPercentValid: false,
      );

  void _finish(_Run run, {bool retired = false}) {
    run.wallEnd = DateTime.now().microsecondsSinceEpoch;
    run.clock.stop();
    run.retired = retired;
    _emit({
      'event': 'end',
      'scenario': run.name,
      'complete': run.complete,
      'retired': retired,
      'errors': run.errors,
    });
  }

  void _report(_Run run) {
    final diagnostic = run.records.isEmpty ? null : run.records.last;
    final frames = _frames.where((frame) {
      final timestamp = frame.timestampInMicroseconds(
        FramePhase.rasterFinishWallTime,
      );
      return timestamp >= run.wallStart &&
          timestamp <= (run.wallEnd ?? run.wallStart);
    }).toList();
    final build =
        frames.map((frame) => frame.buildDuration.inMicroseconds).toList()
          ..sort();
    final raster =
        frames.map((frame) => frame.rasterDuration.inMicroseconds).toList()
          ..sort();
    Map<String, Object?> frameStats(List<int> values) => {
      'maxUs': values.isEmpty ? null : values.last,
      'p95Us': values.isEmpty
          ? null
          : values[((values.length - 1) * .95).ceil()],
      'over16670Us': values.where((value) => value > 16670).length,
    };
    // Keep records below Android's log line limit, without dropping metrics.
    _emit({
      'event': 'scenario_frames',
      'name': run.name,
      'frames': build.length,
      'ui': frameStats(build),
      'raster': frameStats(raster),
    });
    if (run.partialNavigation) {
      final interactionFrames = frames.where((frame) {
        final timestamp = frame.timestampInMicroseconds(
          FramePhase.rasterFinishWallTime,
        );
        return run.interactionWallStart != null &&
            timestamp >= run.interactionWallStart! &&
            timestamp <= run.interactionWallEnd!;
      }).toList();
      final interactionBuild =
          interactionFrames
              .map((frame) => frame.buildDuration.inMicroseconds)
              .toList()
            ..sort();
      final interactionRaster =
          interactionFrames
              .map((frame) => frame.rasterDuration.inMicroseconds)
              .toList()
            ..sort();
      // This window includes real page rendering, animation and background
      // probes. Compare matching actions/windows, not a baseline spinner GPU.
      _emit({
        'event': 'scenario_interaction_frames',
        'name': run.name,
        'window': 'first-readable-to-last-requested-page-visible',
        'valid': run.partialNavigationInvalidReason == null,
        'frames': interactionFrames.length,
        'ui': frameStats(interactionBuild),
        'raster': frameStats(interactionRaster),
      });
      _emit({
        'event': 'scenario_navigation_requests',
        'name': run.name,
        'items': [for (final request in run.pageRequests) request.toJson()],
      });
      _emit(
        navigationProfileSummary(
          name: run.name,
          invalidReason: run.partialNavigationInvalidReason,
          firstReadableWasPartial: run.firstReadableWasPartial,
          requestsWhilePending: run.pageRequests
              .where((request) => request.pending)
              .length,
          uncoveredRequestsWhilePending: run.pageRequests
              .where((request) => request.pending && request.uncovered)
              .length,
          interactionWindowUs: run.interactionWallStart == null
              ? null
              : run.interactionWallEnd! - run.interactionWallStart!,
        ),
      );
    }
    _emit({
      'event': 'scenario_publications',
      'name': run.name,
      'items': [
        for (final record in run.records)
          {
            'complete': record.isComplete,
            'pages': record.pageCount,
            'probes': record.complexSearchProbeCount,
            'candidateTotalCodeUnits': record.totalCandidateHtmlCodeUnits,
          },
      ],
    });
    final result = <String, Object?>{
      'event': 'scenario',
      'name': run.name,
      'passed':
          run.errors.isEmpty &&
          run.lateCallbacks == 0 &&
          (!run.partialNavigation ||
              run.partialNavigationInvalidReason == null) &&
          (run.retired ? run.pendingAtRetirement : run.complete),
      'retired': run.retired,
      'pendingAtRetirement': run.pendingAtRetirement,
      'wallReadyUs': run.readyUs,
      'wallCompleteUs': run.completeUs,
      'windowUs': run.clock.elapsedMicroseconds,
      'diagnosticEvents': run.records.length,
      'partialEvents': run.records.where((record) => !record.isComplete).length,
      'lateCallbacks': run.lateCallbacks,
      'errors': run.errors,
      'visiblePage': run.position?.pageIndex,
      'pages': diagnostic?.pageCount,
      'anchorNode': run.position?.anchor.nodeId,
      'anchorOffset': run.position?.anchor.textOffset,
      'compatibilityRestore': run.position?.isReadOnlyCompatibilityRestore,
      'availableHeight': diagnostic?.availableHeight,
      'cacheHit': diagnostic?.cacheHit,
      'probes': diagnostic?.complexSearchProbeCount,
      'planStatisticsReplayed': diagnostic?.cacheHit ?? false,
      'measurements': diagnostic?.measurementCount,
      'measurementCacheHits': diagnostic?.measurementCacheHitCount,
      'textLayouts': diagnostic?.textLayoutCount,
      'complexBlocks': diagnostic?.complexBlockCount,
      'rendererValidations': diagnostic?.rendererValidationCount,
      'rendererValidationMismatchCount':
          diagnostic?.rendererValidationMismatchCount,
      'domSlices': diagnostic?.domSliceCount,
      'candidateMaxCodeUnits': diagnostic?.maximumCandidateHtmlCodeUnits,
      'candidateTotalCodeUnits': diagnostic?.totalCandidateHtmlCodeUnits,
      'uncachedCandidateCodeUnits': diagnostic?.uncachedCandidateHtmlCodeUnits,
      'prepareUs': diagnostic?.preparationDuration.inMicroseconds,
      'indexUs': diagnostic?.complexBoundaryIndexBuildDuration.inMicroseconds,
      'measureUs': diagnostic?.measurementDuration.inMicroseconds,
      'observedSyncMaxUs':
          diagnostic?.longestSynchronousStepDuration.inMicroseconds,
      'firstPublishedUs':
          diagnostic?.firstPublishedPageDuration?.inMicroseconds,
      'targetAvailableUs':
          diagnostic?.targetPageAvailableDuration.inMicroseconds,
      'firstFrameworkFrameUs':
          diagnostic?.firstVisibleFrameDuration?.inMicroseconds,
      if (run.partialNavigation)
        'partialNavigationValid': run.partialNavigationInvalidReason == null,
    };
    // A plan-cache hit replays stored cold-plan statistics; it is not fresh probe work.
    _results.add(result);
    _emit(result);
  }

  bool _accept(_Run run) {
    if (!identical(_run, run) || !_visible) {
      run.lateCallbacks++;
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    if (!_visible || run == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final episode = NovelEpisodeItem(
      episodeId: run.episodeId,
      novelId: 'profile-novel',
      sourceTid: '1',
      episodeTitle: '',
      orderIndex: 0,
    );
    final theme = Theme.of(context);
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: _preferences,
      theme: theme,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: _preferences,
      theme: theme,
      palette: palette,
    );
    return Scaffold(
      backgroundColor: palette.background,
      body: NovelReaderHtmlPagedSurface(
        key: ValueKey(_generation),
        rawHtml: _html,
        episode: episode,
        preferences: _preferences,
        typography: typography,
        theme: const NovelForumHtmlRenderThemeFactory().fromPalette(palette),
        imageReferer: 'https://bbs.yamibo.com/',
        progressSnapshot: _snapshot,
        semanticDocument: _document,
        paginationCache: _plans,
        paginationMeasureCache: _measures,
        paginationBoundaryCache: _boundaries,
        preparedChapterCache: _prepared,
        navigationController: _navigation,
        pageSeekRequest: _seek,
        diagnosticsSink: _Sink((record) {
          if (_accept(run)) {
            run.records.add(record);
            if (record.isComplete) {
              run.completeUs ??= run.clock.elapsedMicroseconds;
            }
            run.observePageRequests();
          }
        }),
        onContentReady: () {
          if (_accept(run) && run.readyUs == null) {
            run.readyUs = run.clock.elapsedMicroseconds;
            _emit({
              'event': 'ready',
              'scenario': run.name,
              'wallUs': run.readyUs,
            });
            run.completeReadableIfPossible();
          }
        },
        onContentTerminal: () {
          if (_accept(run)) {
            run.errors.add('surface_terminal');
          }
        },
        onPositionChanged: (position) {
          if (_accept(run)) {
            final previous = run.position;
            if (previous != null && previous.pageIndex != position.pageIndex) {
              run.lastPageSpan =
                  (position.anchor.textOffset - previous.anchor.textOffset)
                      .abs();
            }
            run.position = position;
            run.observePageRequests();
            run.completeReadableIfPossible();
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _navigation.dispose();
    _clearCaches();
    super.dispose();
  }
}

class _Sink implements NovelReaderPaginationDiagnosticsSink {
  _Sink(this.accept);
  final void Function(NovelReaderPaginationDiagnostics) accept;
  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) =>
      accept(diagnostics);
}

class _Run {
  _Run(this.name, this.episodeId);
  final String name;
  final String episodeId;
  final clock = Stopwatch()..start();
  final wallStart = DateTime.now().microsecondsSinceEpoch;
  final records = <NovelReaderPaginationDiagnostics>[];
  final errors = <String>[];
  NovelReaderPaginationPosition? position;
  int? readyUs, completeUs, wallEnd, lastPageSpan;
  int lateCallbacks = 0;
  bool retired = false, pendingAtRetirement = false;
  final readable = Completer<void>();
  final pageRequests = <_PageRequest>[];
  bool partialNavigation = false, firstReadableWasPartial = false;
  String? partialNavigationInvalidReason;
  int? interactionWallStart, interactionWallEnd;
  int? availablePages;
  bool get complete => completeUs != null;

  void completeReadableIfPossible() {
    if (!readable.isCompleted && readyUs != null && position != null) {
      readable.complete();
    }
  }

  void observePageRequests({int? visiblePageCount}) {
    final elapsedUs = clock.elapsedMicroseconds;
    for (final request in pageRequests) {
      if (visiblePageCount != null && visiblePageCount > request.target) {
        request.coveredUs ??= elapsedUs;
      }
      if (position?.pageIndex == request.target) {
        request.reachedUs ??= elapsedUs;
        request.reachedWhilePending ??=
            !complete && !position!.isPageCountFinal;
      }
    }
  }
}

class _PageRequest {
  _PageRequest({
    required this.from,
    required this.target,
    required this.requestedUs,
    required this.availablePages,
    required this.pending,
  }) : coveredUs = target < availablePages ? requestedUs : null;

  final int from, target, requestedUs, availablePages;
  final bool pending;
  int? acceptedUs, coveredUs, reachedUs;
  bool? reachedWhilePending;
  int rejectedAttempts = 0;
  bool get uncovered => target >= availablePages;

  Map<String, Object?> toJson() => {
    'fromPage': from,
    'targetPage': target,
    'requestedUs': requestedUs,
    'observedAvailablePagesAtRequest': availablePages,
    'pendingAtRequest': pending,
    'observedUncoveredAtRequest': uncovered,
    'acceptedUs': acceptedUs,
    // Sampling identifies the first observed coverage, not its publish instant.
    'observedCoverageWaitUs': coveredUs == null
        ? null
        : coveredUs! - requestedUs,
    'acceptanceWaitUs': acceptedUs == null ? null : acceptedUs! - requestedUs,
    'visibleWaitUs': reachedUs == null ? null : reachedUs! - requestedUs,
    'reachedWhilePending': reachedWhilePending,
    'rejectedAttempts': rejectedAttempts,
  };
}

final _safeHtml = List<String>.filled(
  40,
  '<p>合成分页正文 mixed 123，只有公开生成文本，重复段落用于观察普通文字布局与换行。</p>',
).join();
final _complexHtml =
    '<p><font face="serif">${List<String>.filled(120, '合成长复杂正文 mixed 123，A👨‍👩‍👧‍👦e\u0301🇨🇳中<ruby>注音<rt>zhuyin</rt></ruby>，连续边界与完整内容。').join()}</font></p>';
