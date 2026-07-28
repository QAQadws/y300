import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/providers/app_update_providers.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';
import 'package:y300/features/app_update/domain/services/app_release_notes_service.dart';
import 'package:y300/features/app_update/presentation/app_release_notes_page.dart';

void main() {
  final version = Version.parse('0.0.6');

  testWidgets('shows a stable empty state for a known empty release', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..notes['0.0.6'] = AppReleaseNotes(
        version: version,
        tag: 'v0.0.6',
        body: '',
        fetchedAt: DateTime.utc(2026, 7, 22),
      );

    await _pumpPage(
      tester,
      version,
      AppReleaseNotesService(
        repository: repository,
        remoteSource: _SequenceRemoteSource(
          const <AppReleaseNotesLoadResult>[],
        ),
      ),
    );

    expect(find.text('当前版本暂无更新日志'), findsOneWidget);
  });

  testWidgets('retries an unavailable release only after user action', (
    tester,
  ) async {
    final remote = _SequenceRemoteSource(<AppReleaseNotesLoadResult>[
      const AppReleaseNotesUnavailable(
        failure: AppUpdateFailure(
          code: AppUpdateFailureCode.networkUnavailable,
          message: 'offline',
        ),
      ),
      AppReleaseNotesAvailable(
        AppReleaseNotes(
          version: version,
          tag: 'v0.0.6',
          body: 'Loaded after retry',
          fetchedAt: DateTime.utc(2026, 7, 22),
        ),
      ),
    ]);
    await _pumpPage(
      tester,
      version,
      AppReleaseNotesService(
        repository: _FakeRepository(),
        remoteSource: remote,
      ),
    );

    expect(find.text('更新日志暂不可用'), findsOneWidget);
    expect(remote.fetchCount, 1);

    await tester.tap(find.byKey(const Key('app-release-notes-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Loaded after retry'), findsOneWidget);
    expect(remote.fetchCount, 2);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Version version,
  AppReleaseNotesService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appReleaseNotesServiceProvider.overrideWithValue(service)],
      child: LocalizedTestApp(
        home: AppReleaseNotesPage(installedVersion: version),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRepository implements AppReleaseNotesRepository {
  final Map<String, AppReleaseNotes> notes = <String, AppReleaseNotes>{};
  final Map<String, DateTime> attempts = <String, DateTime>{};

  @override
  Future<void> recordAttempt(Version version, DateTime attemptedAt) async {
    attempts[version.toString()] = attemptedAt;
  }

  @override
  Future<AppReleaseNotes?> read(Version version) async {
    return notes[version.toString()];
  }

  @override
  Future<DateTime?> readLastAttempt(Version version) async {
    return attempts[version.toString()];
  }

  @override
  Future<void> save(AppReleaseNotes value) async {
    notes[value.version.toString()] = value;
  }
}

final class _SequenceRemoteSource implements AppReleaseNotesRemoteSource {
  _SequenceRemoteSource(this.results);

  final List<AppReleaseNotesLoadResult> results;
  var fetchCount = 0;

  @override
  Future<AppReleaseNotesLoadResult> fetch(Version version) async {
    final result = results[fetchCount];
    fetchCount++;
    return result;
  }
}
