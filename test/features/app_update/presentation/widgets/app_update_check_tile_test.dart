import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/features/app_update/presentation/widgets/app_update_check_tile.dart';

void main() {
  testWidgets('shows the Upgrader version and reports when already current', (
    tester,
  ) async {
    final repository = _FakeRepository(_successLookup());
    final coordinator = AppUpdatePromptCoordinator(
      repository: repository,
      launcher: _FakeLauncher(),
      upgrader: _TileUpgrader(updateAvailable: false),
    );
    addTearDown(coordinator.dispose);

    await _pumpTile(tester, coordinator);

    expect(find.text('当前版本：0.0.1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-check-update-entry')));
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsOneWidget);
    expect(repository.forceRefreshValues, <bool>[true]);
  });

  testWidgets('requests the root prompt when the version is ignored', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    final coordinator = AppUpdatePromptCoordinator(
      repository: _FakeRepository(_successLookup()),
      launcher: launcher,
      upgrader: _TileUpgrader(updateAvailable: true, ignored: true),
    );
    addTearDown(coordinator.dispose);
    final promptRequested = expectLater(
      coordinator.promptRequestStream,
      emits(isNull),
    );

    await _pumpTile(tester, coordinator);
    await tester.tap(find.byKey(const Key('about-check-update-entry')));
    await tester.pumpAndSettle();
    await promptRequested;

    expect(find.textContaining('仍在稍后提醒间隔内'), findsNothing);
    expect(find.text('立即下载'), findsNothing);
    expect(launcher.openedUris, isEmpty);
  });
}

Future<void> _pumpTile(
  WidgetTester tester,
  AppUpdatePromptCoordinator coordinator,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appUpdatePromptCoordinatorProvider.overrideWithValue(coordinator),
      ],
      child: const LocalizedTestApp(home: Scaffold(body: AppUpdateCheckTile())),
    ),
  );
  await tester.pump();
}

final class _TileUpgrader extends Upgrader {
  _TileUpgrader({required this.updateAvailable, this.ignored = false}) {
    updateState(state.copyWith(versionInfo: _versionInfo()));
  }

  final bool updateAvailable;
  final bool ignored;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    final info = _versionInfo();
    updateState(state.copyWith(versionInfo: info));
    return info;
  }

  @override
  bool isUpdateAvailable() => updateAvailable;

  @override
  bool alreadyIgnoredThisVersion() => ignored;

  @override
  bool isTooSoon() => false;
}

UpgraderVersionInfo _versionInfo() {
  return UpgraderVersionInfo(
    installedVersion: Version(0, 0, 1),
    appStoreVersion: Version(0, 0, 2),
    appStoreListingURL: _validApkUri.toString(),
    releaseNotes: 'Release notes',
  );
}

final class _FakeRepository implements GiteeLatestReleaseRepository {
  _FakeRepository(this.result);

  final GiteeReleaseLookupResult result;
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
    forceRefreshValues.add(forceRefresh);
    return result;
  }
}

final class _FakeLauncher implements AppUpdateLauncher {
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<AppUpdateLaunchResult> openApk(Uri apkUri) async {
    openedUris.add(apkUri);
    return const AppUpdateLaunchSuccess();
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

final Uri _validApkUri = Uri.parse(
  'https://gitee.com/QAQadws/y300-releases/releases/download/'
  'v0.0.2/y300-v0.0.2-android-arm64-v8a-release.apk',
);
