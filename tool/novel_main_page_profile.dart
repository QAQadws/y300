// Isolated profile executable. Uses the real reader page, synthetic I/O only.
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import 'novel_inline_soft_space_profile.dart';
import 'novel_main_page_mode_cycle.dart';
import 'novel_main_page_profile_data.dart';
import 'novel_main_page_profile_observation.dart';
import 'novel_main_page_profile_timings.dart';
import 'novel_mixed_first_line_indent_profile.dart';
import 'novel_pagination_profile_config.dart';
import 'novel_pagination_profile_fixtures.dart';
import 'novel_profile_memory.dart';

const _baseline = bool.fromEnvironment('PROFILE_BASELINE');
const _memoryMode = bool.fromEnvironment('PROFILE_MEMORY');
const _chapterCycle = bool.fromEnvironment('PROFILE_CHAPTER_CYCLE');
const _modeCycle = bool.fromEnvironment('PROFILE_MODE_CYCLE');
const _transitionCycle = _chapterCycle || _modeCycle;
const _inlineSoftSpace = bool.fromEnvironment('PROFILE_INLINE_SOFT_SPACE');
const _warmReturn = bool.fromEnvironment('PROFILE_WARM_RETURN');
const _corpus = String.fromEnvironment(
  'PROFILE_CORPUS',
  defaultValue: 'baseline',
);
final _fixtures = _chapterCycle
    ? [(name: 'chapter-cycle', html: novelProfileSafeHtml)]
    : novelMainPageProfileFixtures(_corpus);
const _backend = String.fromEnvironment(
  'PROFILE_BACKEND',
  defaultValue: 'both',
);
const _config = NovelProfileBaselineConfig(
  warmupsPerFixture: int.fromEnvironment('PROFILE_WARMUPS', defaultValue: 5),
  opensPerFixture: int.fromEnvironment('PROFILE_OPENS', defaultValue: 30),
  turnGroups: int.fromEnvironment('PROFILE_TURN_GROUPS', defaultValue: 3),
  turnsPerGroup: int.fromEnvironment('PROFILE_TURNS', defaultValue: 200),
);
final _runtimeErrors = <String>[];
const _memoryOpens = 20;
const _memorySettle = Duration(milliseconds: 250);
final _warmups = _baseline || (_memoryMode && !_transitionCycle)
    ? _config.warmupsPerFixture
    : 0;
final _opens = _memoryMode && !_transitionCycle
    ? _memoryOpens
    : (_baseline ? _config.opensPerFixture : 1);
final _turnGroups = _memoryMode ? 0 : (_baseline ? _config.turnGroups : 1);
const _nativeOpenMilestones = [
  'nativeViewportUs',
  'nativeFirstPagePublishedUs',
  'nativeTargetPreparedUs',
  'nativeTargetConfirmedUs',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _config.validate();
  // Resolve before launching any routes so a misspelled corpus cannot pass as
  // an empty benchmark matrix.
  if (_fixtures.isEmpty) throw StateError('Empty profile corpus');
  if (!['native', 'legacy', 'both'].contains(_backend)) {
    throw ArgumentError('Unknown profile backend');
  }
  if (_memoryMode &&
      (_baseline || _inlineSoftSpace || _warmReturn || _backend == 'both')) {
    throw ArgumentError(
      'Memory sampling requires one backend and no timing diagnostics',
    );
  }
  if (_transitionCycle &&
      ((_chapterCycle && _modeCycle) ||
          !_memoryMode ||
          _backend != 'native' ||
          _corpus != 'baseline')) {
    throw ArgumentError(
      'Select one native memory transition cycle with the built-in corpus',
    );
  }
  final previousError = FlutterError.onError;
  FlutterError.onError = (details) {
    _runtimeErrors.add(details.exception.runtimeType.toString());
    previousError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _runtimeErrors.add(error.runtimeType.toString());
    return true;
  };
  final data = NovelMainPageProfileData();
  runApp(
    data.scope(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _MainPageProfile(data: data),
      ),
    ),
  );
}

class _MainPageProfile extends StatefulWidget {
  const _MainPageProfile({required this.data});
  final NovelMainPageProfileData data;
  @override
  State<_MainPageProfile> createState() => _MainPageProfileState();
}

class _MainPageProfileState extends State<_MainPageProfile> {
  final _frames = ProfileFrameWindows();
  final _runs = <Map<String, Object?>>[];
  final _memory = _memoryMode ? NovelProfileMemory(_emit) : null;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    if (!_memoryMode) SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_suite()));
  }

  void _timings(List<FrameTiming> frames) {
    for (final frame in frames) {
      _frames.add(
        vsyncUs: frame.timestampInMicroseconds(FramePhase.vsyncStart),
        buildUs: frame.buildDuration.inMicroseconds,
        rasterUs: frame.rasterDuration.inMicroseconds,
        totalUs: frame.totalSpan.inMicroseconds,
      );
    }
  }

  int get _frameTime =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;

  Future<void> _nextFrame() async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) throw StateError('Profile host unmounted');
    await SchedulerBinding.instance.endOfFrame;
  }

  Future<ProfileReaderObservation> _wait(
    GlobalKey key,
    NovelReaderArgs args,
    bool Function(ProfileReaderObservation) accepted, {
    bool Function()? observeOpening,
    Duration timeout = const Duration(seconds: 25),
    bool sampleEveryFrame = false,
  }) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      if (sampleEveryFrame) {
        await SchedulerBinding.instance.endOfFrame;
      } else {
        await _nextFrame();
      }
      final context = key.currentContext;
      if (context == null || !context.mounted) continue;
      final observation = observeProfileReader(
        context,
        args,
        observeOpening: observeOpening?.call() ?? false,
      );
      if (observation.failed) {
        throw StateError('Reader reported layout failure');
      }
      if (accepted(observation)) return observation;
    }
    throw TimeoutException('Reader did not reach the requested visible state');
  }

  Future<void> _suite() async {
    // The first Android frame may precede the initial display metrics event.
    // Wait for a nonempty, stable view and its matching inherited MediaQuery.
    ({Size physical, double ratio})? previousMetrics;
    var stableFrames = 0;
    for (var i = 0; i < 250 && stableFrames < 3; i++) {
      await _nextFrame();
      if (!mounted) return;
      final view = View.of(context);
      final media = MediaQuery.of(context);
      final metrics = (
        physical: view.physicalSize,
        ratio: view.devicePixelRatio,
      );
      final matches =
          !view.physicalSize.isEmpty &&
          media.devicePixelRatio == view.devicePixelRatio &&
          (media.size.width * view.devicePixelRatio - view.physicalSize.width)
                  .abs() <
              1 &&
          (media.size.height * view.devicePixelRatio - view.physicalSize.height)
                  .abs() <
              1;
      stableFrames = matches && metrics == previousMetrics
          ? stableFrames + 1
          : 0;
      previousMetrics = metrics;
    }
    if (!mounted) return;
    if (stableFrames < 3) {
      _emit({
        'event': 'suite_done',
        'suitePassed': false,
        'error': 'display_metrics_unavailable',
      });
      if (const bool.fromEnvironment('PROFILE_AUTO_EXIT')) {
        await SystemNavigator.pop();
      }
      return;
    }
    final media = MediaQuery.of(context);
    final refreshRate = View.of(context).display.refreshRate;
    final budget = 1000000 / (refreshRate > 0 ? refreshRate : 60);
    _emit({
      'event': 'suite_start',
      'target': 'NovelReaderPage',
      'revision': const String.fromEnvironment('PROFILE_REVISION'),
      'device': const String.fromEnvironment('PROFILE_DEVICE'),
      'profileMode': kProfileMode,
      'physicalSize': [
        View.of(context).physicalSize.width,
        View.of(context).physicalSize.height,
      ],
      'devicePixelRatio': media.devicePixelRatio,
      'logicalViewport': [media.size.width, media.size.height],
      'refreshRate': refreshRate,
      'frameBudgetUs': budget,
      'textScaleAt18_5': media.textScaler.scale(18.5),
      'font': 'system',
      'fontSize': 18.5,
      'flutterVersion': const String.fromEnvironment('FLUTTER_VERSION'),
      'frameworkRevision': const String.fromEnvironment(
        'FLUTTER_FRAMEWORK_REVISION',
      ),
      'engineRevision': const String.fromEnvironment('FLUTTER_ENGINE_REVISION'),
      'dartVersion': const String.fromEnvironment('FLUTTER_DART_VERSION'),
    });
    _emit({
      'event': 'suite_method',
      'coldDefinition': 'new route, controller, owner, derived caches and position; warm process/fonts; in-memory synthetic I/O',
      'openDefinition': 'uncoveredTarget: laid-out matching body without reader cover; firstReadable: existing observation after route settles; planComplete: finalized plan independent of route animation',
      if (!_memoryMode) ...{
        'openObservation': 'every frame after push',
        'nativeOpenMilestones': 'viewport mounted, first stable page published, target prepared, target confirmed by viewport',
      },
      'turnDefinition': 'reader chrome command to settled visible page; excludes hardware gesture recognition',
      'frameAttribution':
          'engine vsync intervals; batched delivery does not select phase',
      'synthetic': true,
      'baseline': _baseline,
      'memoryMode': _memoryMode,
      if (_chapterCycle) 'chapterCycle': true,
      if (_modeCycle) 'modeCycle': true,
      'sampleConfig': _memoryMode
          ? {
              'warmupsPerFixture': _warmups,
              'opensPerFixture': _opens,
              'settlingMs': _memorySettle.inMilliseconds,
              if (_chapterCycle) ...{
                'chapterWarmups': _config.warmupsPerFixture,
                'chapterRoundTrips': _memoryOpens,
              },
              if (_modeCycle) ...{
                'modeWarmups': _config.warmupsPerFixture,
                'modeRoundTrips': _memoryOpens,
              },
            }
          : _config.toJson(),
      'inlineSoftSpaceRequested': _inlineSoftSpace,
      'warmReturnRequested': _warmReturn,
      'corpus': _corpus,
    });
    var inlineSoftSpaceCases = 0;
    var firstLineIndentCases = 0;
    var mixedFirstLineIndentCases = 0;
    try {
      if (_inlineSoftSpace) {
        for (final record in profileInlineSoftSpaces()) {
          _emit(record);
          inlineSoftSpaceCases++;
        }
        for (final record in profileFirstLineIndents()) {
          _emit(record);
          firstLineIndentCases++;
        }
        for (final record in profileMixedFirstLineIndents(onFailure: _emit)) {
          _emit(record);
          mixedFirstLineIndentCases++;
        }
      }
      for (final native in [false, true]) {
        if (_backend != 'both' && _backend != (native ? 'native' : 'legacy')) {
          continue;
        }
        for (final fixture in _fixtures) {
          for (var i = 0; i < _warmups; i++) {
            await _run(native, fixture, kind: 'warmup', index: i);
            if (_memoryMode && _runs.last['passed'] != true) {
              throw StateError('Memory warmup failed');
            }
          }
          if (_memoryMode && !_transitionCycle) {
            await _sampleMemory('warmed', native, fixture.name);
          }
          for (var i = 0; i < _opens; i++) {
            await _run(
              native,
              fixture,
              kind: 'open',
              index: i,
              reflow: !_baseline && !_memoryMode,
            );
            if (_memoryMode) {
              final run = _runs.last;
              if (run['passed'] != true) {
                throw StateError('Memory lifecycle round failed');
              }
              // The run has returned and no longer holds the route or owner.
              await _sampleMemory(
                'closed',
                native,
                fixture.name,
                run: run['id']! as int,
              );
            }
          }
          for (var group = 0; group < _turnGroups; group++) {
            await _run(
              native,
              fixture,
              kind: 'turns',
              index: group,
              turns: _baseline ? _config.turnsPerGroup : 4,
            );
          }
        }
      }
    } catch (error) {
      _runtimeErrors.add(error.runtimeType.toString());
    }
    // Profile timings are batched by the engine. Keep interval records until
    // the final batch has arrived, without assigning it to the current phase.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _nextFrame();
    var missingFrames = 0;
    var frameReportCount = 0;
    for (final record in _frames.summaries(frameBudgetUs: budget)) {
      missingFrames += record['windowsWithoutFrames']! as int;
      frameReportCount++;
      _emit({'event': 'phase_frames', ...record});
    }
    for (final record in _frames.slowFrames()) {
      frameReportCount++;
      _emit({'event': 'phase_frame_over_50ms', ...record});
    }
    final matrix = <Map<String, Object?>>[];
    for (final backend in ['legacy', 'native']) {
      if (_backend != 'both' && _backend != backend) continue;
      for (final fixture in _fixtures) {
        final runs = _runs.where(
          (run) => run['backend'] == backend && run['fixture'] == fixture.name,
        );
        final opens = runs.where((run) => run['kind'] == 'open').toList();
        final successfulOpens = opens.where((run) => run['passed'] == true);
        final warmups = runs.where((run) => run['kind'] == 'warmup').toList();
        final turns = runs.where((run) => run['kind'] == 'turns').toList();
        final complete =
            warmups.length == _warmups &&
            opens.length == _opens &&
            turns.length == _turnGroups &&
            runs.every((run) => run['passed'] == true) &&
            turns.every(
              (run) => run['completedTurns'] == run['requestedTurns'],
            );
        matrix.add({
          'backend': backend,
          'fixture': fixture.name,
          'samplingCompleted': complete,
          'successfulWarmups': warmups
              .where((run) => run['passed'] == true)
              .length,
          'successfulOpens': successfulOpens.length,
          'completedTurns': turns.map((run) => run['completedTurns']).toList(),
          if (!_memoryMode)
            for (final metric in [
              if (backend == 'native') ..._nativeOpenMilestones,
              'uncoveredTargetUs',
              'routeSettledUs',
              'firstReadableUs',
              'planCompleteUs',
              if (_warmReturn) 'warmReturnUs',
            ])
              metric: profileDistribution(
                successfulOpens.map((run) => run[metric]! as int),
              ),
        });
        _emit({'event': 'sample_summary', ...matrix.last});
      }
    }
    final passed =
        kProfileMode &&
        (!_inlineSoftSpace ||
            inlineSoftSpaceCases == profileInlineSoftSpaceCaseCount &&
                firstLineIndentCases == profileFirstLineIndentCaseCount &&
                mixedFirstLineIndentCases ==
                    profileMixedFirstLineIndentCaseCount) &&
        matrix.every((entry) => entry['samplingCompleted'] == true) &&
        _runtimeErrors.isEmpty &&
        !_frames.overflowed &&
        missingFrames == 0 &&
        widget.data.retainedChapters == 0;
    _emit({
      'event': 'suite_done',
      'target': 'NovelReaderPage',
      'suitePassed': passed,
      'runs': _runs.length,
      'inlineSoftSpaceRequested': _inlineSoftSpace,
      'inlineSoftSpaceCases': inlineSoftSpaceCases,
      'firstLineIndentCases': firstLineIndentCases,
      'mixedFirstLineIndentCases': mixedFirstLineIndentCases,
      'failedRuns': _runs.where((run) => run['passed'] != true).length,
      'runtimeErrorCount': _runtimeErrors.length,
      'runtimeErrorTypes': _runtimeErrors.toSet().take(10).toList(),
      'timingOverflow': _frames.overflowed,
      'windowsWithoutFrames': missingFrames,
      'frameReportCount': frameReportCount,
      'retainedSyntheticChapters': widget.data.retainedChapters,
      if (_memoryMode)
        'expectedMemorySamples':
            matrix.length *
            (_transitionCycle ? 2 + _memoryOpens : 1 + 2 * _memoryOpens),
      'hasRequiredSampleCounts': _baseline && _config.hasRequiredSampleCounts,
      'baselineSamplingCompleted':
          passed && _baseline && _config.hasRequiredSampleCounts,
      'physicalDeviceGateAccepted': false,
      'nativeHeapAndGpuGateAccepted': false,
    });
    if (const bool.fromEnvironment('PROFILE_AUTO_EXIT')) {
      await SystemNavigator.pop();
    }
  }

  Future<void> _sampleMemory(
    String phase,
    bool native,
    String fixture, {
    int? run,
  }) async {
    // Give route disposal and renderer work a consistent settling interval.
    await Future<void>.delayed(_memorySettle);
    await _memory!.checkpoint(
      phase: phase,
      backend: native ? 'native' : 'legacy',
      fixture: fixture,
      run: run,
    );
  }

  Future<ProfileReaderObservation> _cycleChapters(
    GlobalKey key,
    NovelReaderArgs args,
    ProfileReaderObservation initial,
    Map<String, Object?> run,
  ) async {
    final episodes = await widget.data.getEpisodes(novelId: args.novelId);
    final first = episodes.first.episodeId;
    final second = episodes.last.episodeId;
    final owner = initial.nativeOwner!;
    var current = initial;
    Future<void> hop(String target, {required bool forward}) async {
      final previous = current.nativeController!;
      final controls = current.overlay?.bottomBar.progress;
      final command = forward ? controls?.onNext : controls?.onPrevious;
      final enabled = forward
          ? controls?.nextEnabled
          : controls?.previousEnabled;
      if (command == null || enabled != true) {
        throw StateError('Chapter command unavailable');
      }
      command();
      current = await _wait(key, args, (observation) {
        final controller = observation.nativeController;
        return observation.ready &&
            observation.businessConfirmed &&
            observation.complete &&
            observation.frontmost &&
            observation.page == 0 &&
            controller?.visibleView?.coverage.identity.sourceId == target &&
            identical(
              observation.businessController,
              initial.businessController,
            ) &&
            identical(observation.nativeOwner, owner) &&
            !owner.isClosed &&
            owner.activeCacheHandles == 1 &&
            owner.retainedCacheGenerations == 1 &&
            owner.preparationCache.inFlightCount == 0 &&
            profilePagedControllerRetired(previous);
      });
      final coverage = current.nativeController!.visibleView!.coverage;
      if (!coverage.hasLocations || coverage.hasClippedGlyphs) {
        throw StateError('Switched chapter has no readable native coverage');
      }
      run['chapterTransitions'] = (run['chapterTransitions'] as int? ?? 0) + 1;
    }

    return _sampleRoundTrips(run, 'chapter', () async {
      await hop(second, forward: true);
      await hop(first, forward: false);
      return current;
    });
  }

  Future<ProfileReaderObservation> _sampleRoundTrips(
    Map<String, Object?> run,
    String scenario,
    Future<ProfileReaderObservation> Function() next,
  ) async {
    final id = run['id']! as int;
    final warmups = _config.warmupsPerFixture;
    late ProfileReaderObservation current;
    for (var i = 1; i <= warmups + _memoryOpens; i++) {
      current = await next();
      if (i < warmups) continue;
      final round = i - warmups;
      final owner = current.nativeOwner!;
      run['${scenario}RoundTrips'] = round;
      _emit({
        'event': '${scenario}_round_trip',
        'run': id,
        'round': round,
        'activeCacheHandles': owner.activeCacheHandles,
        'cacheGenerations': owner.retainedCacheGenerations,
        'preparedEntries': owner.preparationCache.length,
        'estimatedRetainedBytes': owner.estimatedRetainedBytes,
      });
      await _sampleMemory(
        round == 0 ? '${scenario}_warmed' : '${scenario}_returned',
        true,
        run['fixture']! as String,
        run: id,
      );
    }
    return current;
  }

  Future<void> _run(
    bool native,
    ({String name, String html}) fixture, {
    required String kind,
    required int index,
    int turns = 0,
    bool reflow = false,
  }) async {
    final id = ++_serial;
    final run = <String, Object?>{
      'event': 'page_run',
      'id': id,
      'backend': native ? 'native' : 'legacy',
      'fixture': fixture.name,
      'kind': kind,
      'index': index,
      'requestedTurns': turns,
      'completedTurns': 0,
      'passed': false,
    };
    final source = widget.data.add(
      fixture.html,
      nextChapterHtml: _chapterCycle ? novelProfileComplexHtml : null,
    );
    final args = NovelReaderArgs(
      novelId: source.novelId,
      episodeId: source.episodeId,
    );
    final key = GlobalKey();
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (_) => NovelReaderPage(
        key: key,
        novelId: source.novelId,
        initialEpisodeId: source.episodeId,
        nativePagination: native,
      ),
    );
    ProfileReaderObservation? latest;
    bool windowOpen = false;
    final clock = Stopwatch()..start();
    void begin(String phase, {String? reportGroup}) {
      if (_memoryMode) return;
      _frames.begin(
        '$id/$phase',
        _frameTime,
        reportGroup: reportGroup == null ? null : '$id/$reportGroup',
      );
      windowOpen = true;
    }

    void end() {
      if (!windowOpen) return;
      _frames.end(_frameTime);
      windowOpen = false;
    }

    void observePlanCompletion(ProfileReaderObservation observation) {
      if (observation.complete) {
        run.putIfAbsent('planCompleteUs', () => clock.elapsedMicroseconds);
      }
    }

    void observeNativeOpening(ProfileReaderObservation observation) {
      final controller = observation.nativeController;
      if (controller == null) return;
      final elapsed = clock.elapsedMicroseconds;
      run.putIfAbsent('nativeViewportUs', () => elapsed);
      if (observation.count > 0) {
        run.putIfAbsent('nativeFirstPagePublishedUs', () => elapsed);
      }
      // The viewport may consume the prepared delivery in the same frame.
      if (controller.readyTarget != null || observation.page != null) {
        run.putIfAbsent('nativeTargetPreparedUs', () => elapsed);
      }
      if (observation.page != null) {
        run.putIfAbsent('nativeTargetConfirmedUs', () => elapsed);
      }
    }

    void checkVisiblePage(String phase, ProfileReaderObservation observation) {
      final expected = novelProfileExpectedLanguages(fixture.name);
      if (!native) return;
      final readerContext = key.currentContext;
      final target = observation.nativeController?.viewForPage(
        observation.page!,
      );
      if (readerContext == null || target == null) {
        throw StateError('Native visible delivery is missing');
      }
      if (target.coverage.hasClippedGlyphs) {
        run['clippedGlyphs'] = true;
        throw StateError('Native visible delivery clips glyphs');
      }
      // Check the exact mounted delivery outside timing windows. Inspection
      // never asks a prepared neighbor to acquire resources or become visible.
      final actual = observeNativeProfileLanguages(readerContext, target);
      if (expected == null) return;
      _emit({
        'event': 'page_languages',
        'run': id,
        'phase': phase,
        'page': observation.page,
        'expected': expected.toList()..sort(),
        'actual': actual.toList()..sort(),
      });
      if (!setEquals(actual, expected)) {
        throw StateError('Mounted native language inputs differ from corpus');
      }
    }

    try {
      begin('open');
      unawaited(navigator.push(route));
      final animation = route.animation!;
      run['routeTransitionDurationUs'] =
          route.transitionDuration.inMicroseconds;
      void observeRoute(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          run['routeSettledUs'] = clock.elapsedMicroseconds;
        }
      }

      observeRoute(animation.status);
      animation.addStatusListener(observeRoute);
      try {
        latest = await _wait(
          key,
          args,
          (value) {
            observePlanCompletion(value);
            if (native && !_memoryMode) observeNativeOpening(value);
            if (value.uncoveredTarget) {
              run.putIfAbsent(
                'uncoveredTargetUs',
                () => clock.elapsedMicroseconds,
              );
            }
            return value.ready &&
                value.businessConfirmed &&
                run.containsKey('uncoveredTargetUs');
          },
          observeOpening: () => !run.containsKey('uncoveredTargetUs'),
          sampleEveryFrame: !_memoryMode,
        );
      } finally {
        animation.removeStatusListener(observeRoute);
      }
      run['firstReadableUs'] = clock.elapsedMicroseconds;
      if (native) _emitPageWork(id, 'first', latest);
      run['firstReadableWasPartial'] = !latest.complete;
      end();
      checkVisiblePage('first', latest);
      if (!latest.complete) {
        begin('background');
        latest = await _wait(
          key,
          args,
          (value) {
            observePlanCompletion(value);
            return value.ready && value.complete;
          },
          // The background source yields after sealed pages; a longer corpus
          // may need hundreds of those slots. Reader deadlines are unchanged.
          timeout: _corpus == 'long-text'
              ? const Duration(seconds: 60)
              : const Duration(seconds: 25),
        );
        end();
      }
      run['completeUs'] = clock.elapsedMicroseconds;
      run['pageCount'] = latest.count;
      if (_chapterCycle) {
        latest = await _cycleChapters(key, args, latest, run);
      } else if (_modeCycle) {
        final cycle = NovelProfileModeCycle(
          readerRoute: route,
          waitForReader: (accepted) => _wait(key, args, accepted),
          nextFrame: _nextFrame,
          loadProgress: () => widget.data.getChapterProgress(
            novelId: args.novelId,
            episodeId: args.episodeId,
          ),
          recordStep: (step) => run['modeStep'] = step,
        );
        await cycle.seed(latest);
        latest = await _sampleRoundTrips(run, 'mode', cycle.roundTrip);
      } else if (_memoryMode && kind == 'open') {
        await _sampleMemory('visible', native, fixture.name, run: id);
      }
      if (_warmReturn && kind != 'turns') {
        final before = latest;
        final mountedBefore = before.nativeController?.visibleView;
        final cover = PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: SizedBox.expand()),
        );
        unawaited(navigator.push(cover));
        try {
          await _wait(
            key,
            args,
            (value) =>
                cover.isCurrent &&
                !value.frontmost &&
                (!native || value.nativeController?.isSuspended == true),
          );
          begin('warm-return');
          final returnClock = Stopwatch()..start();
          navigator.pop();
          latest = await _wait(
            key,
            args,
            (value) => value.uncoveredTarget && value.ready,
            observeOpening: () => true,
            sampleEveryFrame: true,
          );
          run['warmReturnUs'] = returnClock.elapsedMicroseconds;
          end();
        } finally {
          if (cover.isCurrent) navigator.pop();
        }
        if (!latest.retainsCompletePlanFrom(before)) {
          throw StateError('Reader did not return to its resident plan');
        }
        if (native) {
          final reused =
              mountedBefore != null &&
              identical(mountedBefore, latest.nativeController?.visibleView);
          run['warmReturnReusedMount'] = reused;
          if (!reused) _emitPageWork(id, 'warm-return', latest);
        }
        checkVisiblePage('warm-return', latest);
      }
      final turnUs = <int>[];
      var forward = true;
      for (var i = 0; i < turns; i++) {
        final next = nextProfileTurn(
          currentPage: latest!.page!,
          pageCount: latest.count,
          forward: forward,
        );
        if (next == null) {
          throw StateError('Chapter cannot support turn samples');
        }
        forward = next.forward;
        final command = forward
            ? latest.overlay?.onRightTap
            : latest.overlay?.onLeftTap;
        if (command == null) {
          throw StateError('Reader chrome command unavailable');
        }
        final targetPrepared =
            latest.nativeController?.viewForPage(next.page) != null;
        begin('turn-$i', reportGroup: 'turns');
        final turnClock = Stopwatch()..start();
        command();
        latest = await _wait(
          key,
          args,
          (value) =>
              value.ready && value.businessConfirmed && value.page == next.page,
        );
        turnUs.add(turnClock.elapsedMicroseconds);
        if (native) {
          _emitPageWork(
            id,
            'turn-$i',
            latest,
            targetPreparedBeforeCommand: targetPrepared,
          );
        }
        end();
        run['completedTurns'] = i + 1;
        checkVisiblePage('turn-$i', latest);
      }
      run['commandToSettledUs'] = profileDistribution(turnUs);
      if (reflow) {
        final oldKey = latest!.paginationKey;
        begin('reflow');
        final reflowClock = Stopwatch()..start();
        latest.businessController!.previewPreferences(
          profileReaderPreferences.copyWith(fontSize: 22),
        );
        latest = await _wait(
          key,
          args,
          (value) => value.ready && value.paginationKey != oldKey,
        );
        run['reflowReadableUs'] = reflowClock.elapsedMicroseconds;
        if (native) _emitPageWork(id, 'reflow', latest);
        end();
        checkVisiblePage('reflow', latest);
      }
      run['passed'] = true;
    } catch (error) {
      run['errorType'] = error.runtimeType.toString();
      run['failedAfterUs'] = clock.elapsedMicroseconds;
      final readerContext = key.currentContext;
      if (readerContext != null && readerContext.mounted) {
        latest = observeProfileReader(readerContext, args);
      }
    } finally {
      end();
      final owner = latest?.nativeOwner;
      final legacyReleased = latest?.legacyCachesReleased;
      latest = null;
      begin('exit');
      final exitClock = Stopwatch()..start();
      navigator.pop();
      await route.completed;
      await _nextFrame();
      end();
      run['exitUs'] = exitClock.elapsedMicroseconds;
      final released = native
          ? owner != null &&
                owner.isClosed &&
                owner.activeCacheHandles == 0 &&
                owner.estimatedRetainedBytes == 0
          : legacyReleased?.call() == true;
      run['ownerCachesReleased'] = released;
      run['routeUnmounted'] = key.currentContext == null;
      if (!released || key.currentContext != null) run['passed'] = false;
      widget.data.release(source.novelId);
      _runs.add(run);
      _emit(run);
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());

  void _emitPageWork(
    int run,
    String phase,
    ProfileReaderObservation observation, {
    bool? targetPreparedBeforeCommand,
  }) {
    final work = observation.nativeWork;
    if (work == null) {
      throw StateError('Visible native delivery has no work record');
    }
    _emit({
      'event': 'page_work',
      'run': run,
      'phase': phase,
      'page': observation.page,
      'targetPreparedBeforeCommand': ?targetPreparedBeforeCommand,
      'preparationUs': work.preparationUs,
      'coverageUs': work.coverageUs,
      'preparationAdvanceUs': work.preparationAdvanceUs,
      'coverageAdvanceUs': work.coverageAdvanceUs,
      'preparationFrames': work.preparationFrames,
      'coverageFrames': work.coverageFrames,
      'preparationSteps': work.preparationSteps,
      'coverageSteps': work.coverageSteps,
      'layoutsBuilt': work.layoutsBuilt,
      'picturesBuilt': work.picturesBuilt,
      'checkedGraphemes': work.checkedGraphemes,
    });
    // Keep cumulative work and single-call warnings in distinct short records.
    // Neither is a frame percentile; a native call cannot be preempted by the
    // outer slice budget merely because its operation count is bounded.
    _emit({
      'event': 'page_advance_budget',
      'run': run,
      'phase': phase,
      'page': observation.page,
      'targetPreparedBeforeCommand': ?targetPreparedBeforeCommand,
      'budgetUs': work.preparationAdvances.budgetUs,
      'preparationMaxUs': work.preparationAdvances.maxUs,
      'coverageMaxUs': work.coverageAdvances.maxUs,
      'preparationOverBudgetSteps': work.preparationAdvances.overBudgetSteps,
      'coverageOverBudgetSteps': work.coverageAdvances.overBudgetSteps,
    });
  }

  @override
  void dispose() {
    if (!_memoryMode) SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }
}

void _emit(Map<String, Object?> record) {
  // Machine-readable small records; never include the displayed body or auth.
  var payload = jsonEncode(record);
  if (utf8.encode('NOVEL_PROFILE $payload').length > 1000) {
    _runtimeErrors.add('profileRecordTooLarge');
    payload = jsonEncode({
      'event': record['event'],
      'suitePassed': false,
      'recordError': 'profileRecordTooLarge',
    });
  }
  // ignore: avoid_print
  print('NOVEL_PROFILE $payload');
}
