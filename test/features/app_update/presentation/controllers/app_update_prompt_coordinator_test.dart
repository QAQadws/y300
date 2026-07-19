import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_check_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdatePromptCoordinator', () {
    test('uses a three-day alert interval for its owned Upgrader', () {
      final coordinator = AppUpdatePromptCoordinator(
        repository: _UnusedRepository(),
        launcher: _RecordingLauncher(),
      );
      addTearDown(coordinator.dispose);

      expect(
        coordinator.upgrader.state.durationUntilAlertAgain,
        AppUpdatePromptCoordinator.alertAgainAfter,
      );
    });

    test('opens the current Upgrader APK URL', () async {
      final upgrader = _RecordingUpgrader();
      _setVersionInfo(upgrader, listingUrl: _validApkUri.toString());
      final launcher = _RecordingLauncher();
      final coordinator = AppUpdatePromptCoordinator(
        repository: _UnusedRepository(),
        launcher: launcher,
        upgrader: upgrader,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.openCurrentUpdate();

      expect(result, isA<AppUpdateLaunchSuccess>());
      expect(launcher.openedUris, <Uri>[_validApkUri]);
    });

    test('coalesces repeated launch requests', () async {
      final upgrader = _RecordingUpgrader();
      _setVersionInfo(upgrader, listingUrl: _validApkUri.toString());
      final completer = Completer<AppUpdateLaunchResult>();
      final launcher = _RecordingLauncher(nextResult: completer.future);
      final coordinator = AppUpdatePromptCoordinator(
        repository: _UnusedRepository(),
        launcher: launcher,
        upgrader: upgrader,
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.openCurrentUpdate();
      final second = coordinator.openCurrentUpdate();

      expect(launcher.openedUris, <Uri>[_validApkUri]);
      completer.complete(const AppUpdateLaunchSuccess());
      expect(await first, isA<AppUpdateLaunchSuccess>());
      expect(await second, isA<AppUpdateLaunchSuccess>());
      expect(launcher.openedUris, hasLength(1));
    });

    test(
      'rejects missing listing URLs without invoking the launcher',
      () async {
        final upgrader = _RecordingUpgrader();
        _setVersionInfo(upgrader, listingUrl: null);
        final launcher = _RecordingLauncher();
        final coordinator = AppUpdatePromptCoordinator(
          repository: _UnusedRepository(),
          launcher: launcher,
          upgrader: upgrader,
        );
        addTearDown(coordinator.dispose);

        final result = await coordinator.openCurrentUpdate();

        expect(_failureCode(result), AppUpdateFailureCode.invalidAssetUrl);
        expect(launcher.openedUris, isEmpty);
      },
    );

    test('disposes its Upgrader exactly once', () {
      final upgrader = _RecordingUpgrader();
      final coordinator = AppUpdatePromptCoordinator(
        repository: _UnusedRepository(),
        launcher: _RecordingLauncher(),
        upgrader: upgrader,
      );

      coordinator.dispose();
      coordinator.dispose();

      expect(upgrader.disposeCalls, 1);
    });

    test('force refreshes once and reports an up-to-date release', () async {
      final repository = _RecordingRepository(Future.value(_successLookup()));
      final upgrader = _CheckUpgrader(updateAvailable: false);
      final coordinator = AppUpdatePromptCoordinator(
        repository: repository,
        launcher: _RecordingLauncher(),
        upgrader: upgrader,
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.checkNow();

      expect(result, isA<AppUpdateCheckUpToDate>());
      expect(repository.forceRefreshValues, <bool>[true]);
      expect(upgrader.initializeCalls, 1);
      expect(upgrader.updateVersionInfoCalls, 1);
    });

    test('coalesces repeated manual checks into one forced lookup', () async {
      final completer = Completer<GiteeReleaseLookupResult>();
      final repository = _RecordingRepository(completer.future);
      final upgrader = _CheckUpgrader(updateAvailable: false);
      final coordinator = AppUpdatePromptCoordinator(
        repository: repository,
        launcher: _RecordingLauncher(),
        upgrader: upgrader,
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.checkNow();
      final second = coordinator.checkNow();
      expect(repository.forceRefreshValues, <bool>[true]);

      completer.complete(_successLookup());

      expect(await first, isA<AppUpdateCheckUpToDate>());
      expect(await second, isA<AppUpdateCheckUpToDate>());
      expect(repository.forceRefreshValues, hasLength(1));
      expect(upgrader.updateVersionInfoCalls, 1);
    });

    test(
      'preserves Upgrader suppression reasons for available updates',
      () async {
        for (final scenario
            in <
              ({
                bool ignored,
                bool tooSoon,
                AppUpdatePromptSuppression? expected,
              })
            >[
              (ignored: false, tooSoon: false, expected: null),
              (
                ignored: true,
                tooSoon: true,
                expected: AppUpdatePromptSuppression.ignored,
              ),
              (
                ignored: false,
                tooSoon: true,
                expected: AppUpdatePromptSuppression.reminderInterval,
              ),
            ]) {
          final coordinator = AppUpdatePromptCoordinator(
            repository: _RecordingRepository(Future.value(_successLookup())),
            launcher: _RecordingLauncher(),
            upgrader: _CheckUpgrader(
              updateAvailable: true,
              ignored: scenario.ignored,
              tooSoon: scenario.tooSoon,
            ),
          );

          final result = await coordinator.checkNow();
          coordinator.dispose();

          expect(result, isA<AppUpdateCheckAvailable>());
          expect(
            (result as AppUpdateCheckAvailable).suppression,
            scenario.expected,
          );
        }
      },
    );

    test('returns the typed repository failure to manual UI', () async {
      const failure = AppUpdateFailure(
        code: AppUpdateFailureCode.rateLimited,
        message: 'rate limited',
      );
      final coordinator = AppUpdatePromptCoordinator(
        repository: _RecordingRepository(
          Future.value(
            const GiteeReleaseLookupFailure(
              failure: failure,
              source: GiteeReleaseLookupSource.network,
            ),
          ),
        ),
        launcher: _RecordingLauncher(),
        upgrader: _CheckUpgrader(updateAvailable: false),
      );
      addTearDown(coordinator.dispose);

      final result = await coordinator.checkNow();

      expect(result, isA<AppUpdateCheckFailure>());
      expect((result as AppUpdateCheckFailure).failure, same(failure));
    });
  });
}

void _setVersionInfo(
  _RecordingUpgrader upgrader, {
  required String? listingUrl,
}) {
  upgrader.updateState(
    upgrader.state.copyWith(
      versionInfo: UpgraderVersionInfo(
        installedVersion: Version(0, 0, 1),
        appStoreVersion: Version(0, 0, 2),
        appStoreListingURL: listingUrl,
      ),
    ),
  );
}

final Uri _validApkUri = Uri.parse(
  'https://gitee.com/QAQadws/y300-releases/releases/download/'
  'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
);

AppUpdateFailureCode _failureCode(AppUpdateLaunchResult result) {
  expect(result, isA<AppUpdateLaunchFailure>());
  return (result as AppUpdateLaunchFailure).failure.code;
}

final class _RecordingLauncher implements AppUpdateLauncher {
  _RecordingLauncher({Future<AppUpdateLaunchResult>? nextResult})
    : _nextResult = nextResult;

  final Future<AppUpdateLaunchResult>? _nextResult;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<AppUpdateLaunchResult> openApk(Uri apkUri) {
    openedUris.add(apkUri);
    return _nextResult ?? Future.value(const AppUpdateLaunchSuccess());
  }
}

final class _RecordingUpgrader extends Upgrader {
  int disposeCalls = 0;

  @override
  void dispose() {
    disposeCalls += 1;
    super.dispose();
  }
}

final class _CheckUpgrader extends Upgrader {
  _CheckUpgrader({
    required this.updateAvailable,
    this.ignored = false,
    this.tooSoon = false,
  }) {
    updateState(
      state.copyWith(
        versionInfo: UpgraderVersionInfo(
          installedVersion: Version(0, 0, 1),
          appStoreVersion: Version(0, 0, 2),
          appStoreListingURL: _validApkUri.toString(),
        ),
      ),
    );
  }

  final bool updateAvailable;
  final bool ignored;
  final bool tooSoon;
  int initializeCalls = 0;
  int updateVersionInfoCalls = 0;

  @override
  Future<bool> initialize() async {
    initializeCalls += 1;
    return true;
  }

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    updateVersionInfoCalls += 1;
    updateStream();
    return state.versionInfo;
  }

  @override
  bool isUpdateAvailable() => updateAvailable;

  @override
  bool alreadyIgnoredThisVersion() => ignored;

  @override
  bool isTooSoon() => tooSoon;
}

final class _RecordingRepository implements GiteeLatestReleaseRepository {
  _RecordingRepository(this.result);

  final Future<GiteeReleaseLookupResult> result;
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false}) {
    forceRefreshValues.add(forceRefresh);
    return result;
  }
}

GiteeReleaseLookupSuccess _successLookup() {
  return GiteeReleaseLookupSuccess(
    candidate: GiteeReleaseCandidate(
      tag: 'v0.0.2',
      version: Version(0, 0, 2),
      apkUri: _validApkUri,
      checksumUri: Uri.parse('$_validApkUri.sha256'),
      releaseNotes: 'Release notes',
    ),
    source: GiteeReleaseLookupSource.network,
  );
}

final class _UnusedRepository implements GiteeLatestReleaseRepository {
  @override
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false}) {
    throw StateError('Repository should not be called by this test.');
  }
}
