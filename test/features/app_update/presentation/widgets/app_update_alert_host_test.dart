import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/features/app_update/presentation/app_update_upgrader.dart';
import 'package:y300/features/app_update/presentation/widgets/app_update_alert_host.dart';
import 'package:y300/features/app_update/presentation/widgets/app_update_check_tile.dart';

void main() {
  testWidgets(
    'shows UpgradeAlert and delegates update without default store launch',
    (tester) async {
      final upgrader = _DisplayUpgrader();
      _setVersionInfo(upgrader);
      final launcher = _FakeLauncher(const AppUpdateLaunchSuccess());
      final coordinator = AppUpdatePromptCoordinator(
        repository: _UnusedRepository(),
        launcher: launcher,
        upgrader: upgrader,
      );
      addTearDown(coordinator.dispose);

      await _pumpHost(tester, coordinator);

      expect(find.byKey(const Key('upgrader_alert_dialog')), findsOneWidget);
      expect(find.text('Release notes'), findsOneWidget);
      expect(find.text('IGNORE'), findsOneWidget);
      expect(find.text('LATER'), findsOneWidget);

      await tester.tap(find.text('UPDATE NOW'));
      await tester.pumpAndSettle();

      expect(launcher.openedUris, <Uri>[_validApkUri]);
      expect(upgrader.defaultStoreLaunchCalls, 0);
      expect(find.byKey(const Key('upgrader_alert_dialog')), findsNothing);
    },
  );

  testWidgets('shows transient feedback when external launch fails', (
    tester,
  ) async {
    final upgrader = _DisplayUpgrader();
    _setVersionInfo(upgrader);
    final launcher = _FakeLauncher(
      const AppUpdateLaunchFailure(
        AppUpdateFailure(
          code: AppUpdateFailureCode.externalLaunchUnavailable,
          message: 'unavailable',
        ),
      ),
    );
    final coordinator = AppUpdatePromptCoordinator(
      repository: _UnusedRepository(),
      launcher: launcher,
      upgrader: upgrader,
    );
    addTearDown(coordinator.dispose);

    await _pumpHost(tester, coordinator);
    await tester.tap(find.text('UPDATE NOW'));
    await tester.pumpAndSettle();

    expect(find.text('无法打开下载链接，请确认设备已安装浏览器'), findsOneWidget);
    expect(upgrader.defaultStoreLaunchCalls, 0);
  });

  testWidgets('stays silent when Upgrader suppresses the prompt', (
    tester,
  ) async {
    final upgrader = _DisplayUpgrader(displayUpgrade: false);
    _setVersionInfo(upgrader);
    final launcher = _FakeLauncher(const AppUpdateLaunchSuccess());
    final coordinator = AppUpdatePromptCoordinator(
      repository: _UnusedRepository(),
      launcher: launcher,
      upgrader: upgrader,
    );
    addTearDown(coordinator.dispose);

    await _pumpHost(tester, coordinator);

    expect(find.byKey(const Key('upgrader_alert_dialog')), findsNothing);
    expect(find.text('content'), findsOneWidget);
    expect(launcher.openedUris, isEmpty);
  });

  testWidgets('manual check reuses the existing root UpgradeAlert', (
    tester,
  ) async {
    final upgrader = _DisplayUpgrader(
      updateAvailable: true,
      versionInfoOnUpdate: _versionInfo(),
    );
    final coordinator = AppUpdatePromptCoordinator(
      repository: _ResultRepository(_successLookup()),
      launcher: _FakeLauncher(const AppUpdateLaunchSuccess()),
      upgrader: upgrader,
    );
    addTearDown(coordinator.dispose);

    await _pumpHost(
      tester,
      coordinator,
      child: const Scaffold(body: AppUpdateCheckTile()),
    );
    expect(find.byKey(const Key('upgrader_alert_dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('about-check-update-entry')));
    await tester.pumpAndSettle();

    expect(upgrader.state.versionInfo, isNotNull);
    expect(find.byKey(const Key('upgrader_alert_dialog')), findsOneWidget);
    expect(upgrader.defaultStoreLaunchCalls, 0);
  });

  testWidgets('manual check bypasses the reminder interval', (tester) async {
    final upgrader = _DisplayUpgrader(
      displayUpgrade: false,
      updateAvailable: true,
      reminderInterval: true,
      versionInfoOnUpdate: _versionInfo(),
    );
    final coordinator = AppUpdatePromptCoordinator(
      repository: _ResultRepository(_successLookup()),
      launcher: _FakeLauncher(const AppUpdateLaunchSuccess()),
      upgrader: upgrader,
    );
    addTearDown(coordinator.dispose);

    await _pumpHost(
      tester,
      coordinator,
      child: const Scaffold(body: AppUpdateCheckTile()),
    );
    expect(find.byKey(const Key('upgrader_alert_dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('about-check-update-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upgrader_alert_dialog')), findsOneWidget);
  });
}

Future<void> _pumpHost(
  WidgetTester tester,
  AppUpdatePromptCoordinator coordinator, {
  Widget child = const Scaffold(body: Text('content')),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appUpdatePromptCoordinatorProvider.overrideWithValue(coordinator),
      ],
      child: LocalizedTestApp(
        locale: Locale('en'),
        supportedLocales: const [Locale('en')],
        home: AppUpdateAlertHost(child: child),
      ),
    ),
  );
  coordinator.upgrader.updateStream();
  await tester.pumpAndSettle();
}

void _setVersionInfo(_DisplayUpgrader upgrader) {
  upgrader.updateState(upgrader.state.copyWith(versionInfo: _versionInfo()));
}

UpgraderVersionInfo _versionInfo() {
  return UpgraderVersionInfo(
    installedVersion: Version(0, 0, 1),
    appStoreVersion: Version(0, 0, 2),
    appStoreListingURL: _validApkUri.toString(),
    releaseNotes: 'Release notes',
  );
}

final Uri _validApkUri = Uri.parse(
  'https://gitee.com/QAQadws/y300-releases/releases/download/'
  'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
);

final class _DisplayUpgrader extends Upgrader
    implements AppUpdateManualPromptGate {
  _DisplayUpgrader({
    this.displayUpgrade = true,
    this.updateAvailable = false,
    this.reminderInterval = false,
    this.versionInfoOnUpdate,
  });

  final bool displayUpgrade;
  final bool updateAvailable;
  final bool reminderInterval;
  final UpgraderVersionInfo? versionInfoOnUpdate;
  int initializeCalls = 0;
  int defaultStoreLaunchCalls = 0;

  @override
  Future<bool> initialize() async {
    initializeCalls += 1;
    return true;
  }

  @override
  String appName() => 'Y300';

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    final info = versionInfoOnUpdate;
    if (info != null) {
      updateState(state.copyWith(versionInfo: info));
    }
    return info;
  }

  @override
  bool isUpdateAvailable() => updateAvailable;

  @override
  bool shouldDisplayUpgrade() {
    if (_manualPromptPending) {
      _manualPromptPending = false;
      return updateAvailable;
    }
    return displayUpgrade;
  }

  bool _manualPromptPending = false;

  @override
  bool isTooSoon() => reminderInterval;

  @override
  void prepareManualPrompt() {
    _manualPromptPending = true;
  }

  @override
  void cancelManualPrompt() {
    _manualPromptPending = false;
  }

  @override
  Future<void> sendUserToAppStore() async {
    defaultStoreLaunchCalls += 1;
  }
}

final class _FakeLauncher implements AppUpdateLauncher {
  _FakeLauncher(this.result);

  final AppUpdateLaunchResult result;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<AppUpdateLaunchResult> openApk(Uri apkUri) async {
    openedUris.add(apkUri);
    return result;
  }
}

final class _UnusedRepository implements GiteeLatestReleaseRepository {
  @override
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false}) {
    throw StateError('Repository should not be called by this test.');
  }
}

final class _ResultRepository implements GiteeLatestReleaseRepository {
  _ResultRepository(this.result);

  final GiteeReleaseLookupResult result;

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
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
