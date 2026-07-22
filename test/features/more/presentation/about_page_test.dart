import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/app_update_launch_result.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_release_notes_service.dart';
import 'package:y300/features/app_update/domain/services/app_update_launcher.dart';
import 'package:y300/features/app_update/presentation/controllers/app_update_prompt_coordinator.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/more/data/about_providers.dart';
import 'package:y300/features/more/domain/models/about_app_info.dart';
import 'package:y300/features/more/domain/services/about_external_link_launcher.dart';
import 'package:y300/features/more/presentation/about_page.dart';

void main() {
  testWidgets(
    'renders the compact about page and opens current release notes',
    (tester) async {
      final version = Version.parse('0.0.6');
      final notesRepository = _FakeNotesRepository()
        ..notes['0.0.6'] = AppReleaseNotes(
          version: version,
          tag: 'v0.0.6',
          body: 'Current version changes',
          fetchedAt: DateTime.utc(2026, 7, 22),
        );
      final externalLauncher = _FakeExternalLauncher();
      final coordinator = _coordinator();
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aboutAppInfoProvider.overrideWith(
              (ref) async =>
                  const AboutAppInfo(version: '0.0.6', buildNumber: '9'),
            ),
            aboutExternalLinkLauncherProvider.overrideWithValue(
              externalLauncher,
            ),
            appUpdatePromptCoordinatorProvider.overrideWithValue(coordinator),
            appReleaseNotesServiceProvider.overrideWithValue(
              AppReleaseNotesService(
                repository: notesRepository,
                remoteSource: const _UnusedRemoteSource(),
              ),
            ),
          ],
          child: const MaterialApp(home: AboutPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Y300'), findsOneWidget);
      expect(find.text('版本 0.0.6 (9)'), findsOneWidget);
      expect(find.byKey(const Key('about-check-update-entry')), findsOneWidget);
      expect(
        find.byKey(const Key('about-release-notes-entry')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('about-github-entry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('about-github-entry')));
      await tester.pump();
      expect(externalLauncher.openedUris, <Uri>[AboutPage.githubRepositoryUri]);

      await tester.tap(find.byKey(const Key('about-release-notes-entry')));
      await tester.pumpAndSettle();

      expect(find.text('Current version changes'), findsOneWidget);
      expect(find.text('Y300 v0.0.6'), findsOneWidget);
    },
  );

  testWidgets('shows feedback when the GitHub repository cannot open', (
    tester,
  ) async {
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aboutAppInfoProvider.overrideWith(
            (ref) async =>
                const AboutAppInfo(version: '0.0.6', buildNumber: '9'),
          ),
          aboutExternalLinkLauncherProvider.overrideWithValue(
            _FakeExternalLauncher(openResult: false),
          ),
          appUpdatePromptCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-github-entry')));
    await tester.pumpAndSettle();

    expect(find.text('无法打开 GitHub 仓库'), findsOneWidget);
  });

  testWidgets('keeps the five-tap diagnostic gesture on the app icon', (
    tester,
  ) async {
    final diagnosticController = _FakeSyncDiagnosticModeController();
    final coordinator = _coordinator();
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aboutAppInfoProvider.overrideWith(
            (ref) async =>
                const AboutAppInfo(version: '0.0.6', buildNumber: '9'),
          ),
          syncDiagnosticModeControllerProvider.overrideWith(
            () => diagnosticController,
          ),
          appUpdatePromptCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byKey(const Key('about-app-icon-tap-target')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(diagnosticController.toggleCount, 1);
    expect(find.textContaining('诊断日志模式已开启'), findsOneWidget);
  });
}

AppUpdatePromptCoordinator _coordinator() {
  return AppUpdatePromptCoordinator(
    repository: const _UnusedLatestRepository(),
    launcher: const _UnusedUpdateLauncher(),
    upgrader: _AboutUpgrader(),
  );
}

final class _AboutUpgrader extends Upgrader {
  _AboutUpgrader() {
    updateState(
      state.copyWith(
        versionInfo: UpgraderVersionInfo(
          installedVersion: Version.parse('0.0.6'),
          appStoreVersion: Version.parse('0.0.6'),
        ),
      ),
    );
  }
}

final class _FakeExternalLauncher implements AboutExternalLinkLauncher {
  _FakeExternalLauncher({this.openResult = true});

  final bool openResult;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    openedUris.add(uri);
    return openResult;
  }
}

final class _FakeNotesRepository implements AppReleaseNotesRepository {
  final Map<String, AppReleaseNotes> notes = <String, AppReleaseNotes>{};

  @override
  Future<void> recordAttempt(Version version, DateTime attemptedAt) async {}

  @override
  Future<AppReleaseNotes?> read(Version version) async {
    return notes[version.toString()];
  }

  @override
  Future<DateTime?> readLastAttempt(Version version) async => null;

  @override
  Future<void> save(AppReleaseNotes value) async {
    notes[value.version.toString()] = value;
  }
}

final class _UnusedRemoteSource implements AppReleaseNotesRemoteSource {
  const _UnusedRemoteSource();

  @override
  Future<AppReleaseNotesLoadResult> fetch(Version version) async {
    return const AppReleaseNotesUnavailable(
      failure: AppUpdateFailure(
        code: AppUpdateFailureCode.remoteUnavailable,
        message: 'unused',
      ),
    );
  }
}

final class _UnusedLatestRepository implements GiteeLatestReleaseRepository {
  const _UnusedLatestRepository();

  @override
  Future<GiteeReleaseLookupResult> getLatest({bool forceRefresh = false}) {
    throw UnimplementedError();
  }
}

final class _UnusedUpdateLauncher implements AppUpdateLauncher {
  const _UnusedUpdateLauncher();

  @override
  Future<AppUpdateLaunchResult> openApk(Uri apkUri) {
    throw UnimplementedError();
  }
}

final class _FakeSyncDiagnosticModeController
    extends SyncDiagnosticModeController {
  var toggleCount = 0;
  var _enabled = false;

  @override
  Future<bool> build() async => _enabled;

  @override
  Future<bool> toggle() async {
    toggleCount++;
    _enabled = !_enabled;
    state = AsyncData(_enabled);
    return _enabled;
  }
}
