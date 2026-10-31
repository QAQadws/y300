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

import 'novel_main_page_profile_data.dart';
import 'novel_main_page_profile_observation.dart';
import 'novel_main_page_profile_timings.dart';
import 'novel_pagination_profile_config.dart';
import 'novel_pagination_profile_fixtures.dart';

const _baseline = bool.fromEnvironment('PROFILE_BASELINE');
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
    bool Function(ProfileReaderObservation) accepted,
  ) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 25)) {
      await _nextFrame();
      final context = key.currentContext;
      if (context == null || !context.mounted) continue;
      final observation = observeProfileReader(context, args);
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
      'turnDefinition': 'reader chrome command to settled visible page; excludes hardware gesture recognition',
      'frameAttribution':
          'engine vsync intervals; batched delivery does not select phase',
      'synthetic': true,
      'baseline': _baseline,
      'sampleConfig': _config.toJson(),
    });
    try {
      for (final native in [false, true]) {
        if (_backend != 'both' && _backend != (native ? 'native' : 'legacy')) {
          continue;
        }
        for (final fixture in novelProfileFixtures) {
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
    final timingRecords = _frames.windows
        .map((window) => window.toJson(frameBudgetUs: budget))
        .toList();
    final missingFrames = timingRecords
        .where((record) => record['frameCount'] == 0)
        .length;
    for (final record in timingRecords) {
      _emit({'event': 'phase_frames', ...record});
    }
    final matrix = <Map<String, Object?>>[];
    for (final backend in ['legacy', 'native']) {
      if (_backend != 'both' && _backend != backend) continue;
      for (final fixture in novelProfileFixtures) {
        final runs = _runs.where(
          (run) => run['backend'] == backend && run['fixture'] == fixture.name,
        );
        final opens = runs.where((run) => run['kind'] == 'open').toList();
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
          'successfulOpens': opens.where((run) => run['passed'] == true).length,
          'completedTurns': turns.map((run) => run['completedTurns']).toList(),
          'firstReadableUs': profileDistribution(
            opens
                .where((run) => run['passed'] == true)
                .map((run) => run['firstReadableUs']! as int),
          ),
        });
        _emit({'event': 'sample_summary', ...matrix.last});
      }
    }
    final passed =
        kProfileMode &&
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
      'failedRuns': _runs.where((run) => run['passed'] != true).length,
      'runtimeErrorCount': _runtimeErrors.length,
      'runtimeErrorTypes': _runtimeErrors.toSet().take(10).toList(),
      'timingOverflow': _frames.overflowed,
      'windowsWithoutFrames': missingFrames,
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
    void begin(String phase) {
      _frames.begin('$id/$phase', _frameTime);
      windowOpen = true;
    }

    void end() {
      if (!windowOpen) return;
      _frames.end(_frameTime);
      windowOpen = false;
    }

    try {
      begin('open');
      unawaited(navigator.push(route));
      latest = await _wait(
        key,
        args,
        (value) => value.ready && value.businessConfirmed,
      );
      run['firstReadableUs'] = clock.elapsedMicroseconds;
      run['firstReadableWasPartial'] = !latest.complete;
      end();
      if (!latest.complete) {
        begin('background');
        latest = await _wait(
          key,
          args,
          (value) => value.ready && value.complete,
        );
        end();
      }
      run['completeUs'] = clock.elapsedMicroseconds;
      run['pageCount'] = latest.count;
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
        begin('turn-$i');
        final turnClock = Stopwatch()..start();
        command();
        latest = await _wait(
          key,
          args,
          (value) =>
              value.ready && value.businessConfirmed && value.page == next.page,
        );
        turnUs.add(turnClock.elapsedMicroseconds);
        end();
        run['completedTurns'] = i + 1;
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
        end();
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
