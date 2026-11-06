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
import 'novel_main_page_profile_data.dart';
import 'novel_main_page_profile_observation.dart';
import 'novel_main_page_profile_timings.dart';
import 'novel_mixed_first_line_indent_profile.dart';
import 'novel_pagination_profile_config.dart';
import 'novel_pagination_profile_fixtures.dart';

const _baseline = bool.fromEnvironment('PROFILE_BASELINE');
const _inlineSoftSpace = bool.fromEnvironment('PROFILE_INLINE_SOFT_SPACE');
const _warmReturn = bool.fromEnvironment('PROFILE_WARM_RETURN');
const _corpus = String.fromEnvironment(
  'PROFILE_CORPUS',
  defaultValue: 'baseline',
);
final _fixtures = novelMainPageProfileFixtures(_corpus);
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _config.validate();
  // Resolve before launching any routes so a misspelled corpus cannot pass as
  // an empty benchmark matrix.
  if (_fixtures.isEmpty) throw StateError('Empty profile corpus');
  if (!['native', 'legacy', 'both'].contains(_backend)) {
    throw ArgumentError('Unknown profile backend');
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
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
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
      'turnDefinition': 'reader chrome command to settled visible page; excludes hardware gesture recognition',
      'frameAttribution':
          'engine vsync intervals; batched delivery does not select phase',
      'synthetic': true,
      'baseline': _baseline,
      'sampleConfig': _config.toJson(),
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
          for (
            var i = 0;
            i < (_baseline ? _config.warmupsPerFixture : 0);
            i++
          ) {
            await _run(native, fixture, kind: 'warmup', index: i);
          }
          for (var i = 0; i < (_baseline ? _config.opensPerFixture : 1); i++) {
            await _run(
              native,
              fixture,
              kind: 'open',
              index: i,
              reflow: !_baseline,
            );
          }
          for (
            var group = 0;
            group < (_baseline ? _config.turnGroups : 1);
            group++
          ) {
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
            warmups.length == (_baseline ? _config.warmupsPerFixture : 0) &&
            opens.length == (_baseline ? _config.opensPerFixture : 1) &&
            turns.length == (_baseline ? _config.turnGroups : 1) &&
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
          for (final metric in [
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
    final source = widget.data.add(fixture.html);
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
        latest = await _wait(key, args, (value) {
          observePlanCompletion(value);
          if (value.uncoveredTarget) {
            run.putIfAbsent(
              'uncoveredTargetUs',
              () => clock.elapsedMicroseconds,
            );
          }
          return value.ready &&
              value.businessConfirmed &&
              run.containsKey('uncoveredTargetUs');
        }, observeOpening: () => !run.containsKey('uncoveredTargetUs'));
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
      if (_warmReturn && kind != 'turns') {
        final before = latest;
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
        if (native) _emitPageWork(id, 'warm-return', latest);
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
      widget.data.release(source.episodeId);
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
    SchedulerBinding.instance.removeTimingsCallback(_timings);
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
