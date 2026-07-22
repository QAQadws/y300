import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';
import 'package:y300/features/app_update/domain/services/app_release_notes_service.dart';

void main() {
  final version = Version.parse('0.0.6');
  final now = DateTime.utc(2026, 7, 22, 12);

  test('returns persisted notes without calling the network', () async {
    final repository = _FakeRepository()
      ..notes['0.0.6'] = _notes(version, now: now);
    final remote = _FakeRemoteSource();
    final service = AppReleaseNotesService(
      repository: repository,
      remoteSource: remote,
      now: () => now,
    );

    final result = await service.loadCurrent(version);

    expect(result, isA<AppReleaseNotesAvailable>());
    expect(remote.fetchCount, 0);
  });

  test('fetches once, persists, and reuses the session result', () async {
    final repository = _FakeRepository();
    final remote = _FakeRemoteSource(
      result: AppReleaseNotesAvailable(_notes(version, now: now)),
    );
    final service = AppReleaseNotesService(
      repository: repository,
      remoteSource: remote,
      now: () => now,
    );

    final first = await service.loadCurrent(version);
    final second = await service.loadCurrent(version);

    expect(first, isA<AppReleaseNotesAvailable>());
    expect(second, isA<AppReleaseNotesAvailable>());
    expect(remote.fetchCount, 1);
    expect(repository.notes['0.0.6']?.body, 'Current release');
  });

  test(
    'defers automatic retry for six hours but allows forced retry',
    () async {
      final repository = _FakeRepository()
        ..attempts['0.0.6'] = now.subtract(const Duration(hours: 1));
      final remote = _FakeRemoteSource(
        result: AppReleaseNotesAvailable(_notes(version, now: now)),
      );
      final service = AppReleaseNotesService(
        repository: repository,
        remoteSource: remote,
        now: () => now,
      );

      final deferred = await service.loadCurrent(version);
      final forced = await service.loadCurrent(version, forceRefresh: true);

      expect(deferred, isA<AppReleaseNotesUnavailable>());
      expect((deferred as AppReleaseNotesUnavailable).retryDeferred, isTrue);
      expect(forced, isA<AppReleaseNotesAvailable>());
      expect(remote.fetchCount, 1);
    },
  );

  test('coalesces concurrent requests for the same version', () async {
    final completer = Completer<AppReleaseNotesLoadResult>();
    final remote = _FakeRemoteSource(futureResult: completer.future);
    final service = AppReleaseNotesService(
      repository: _FakeRepository(),
      remoteSource: remote,
      now: () => now,
    );

    final first = service.loadCurrent(version);
    final second = service.loadCurrent(version, forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    completer.complete(AppReleaseNotesAvailable(_notes(version, now: now)));

    expect(await first, isA<AppReleaseNotesAvailable>());
    expect(await second, isA<AppReleaseNotesAvailable>());
    expect(remote.fetchCount, 1);
  });

  test(
    'candidate persistence failure does not escape and remains available',
    () async {
      final failures = <Object>[];
      final repository = _FakeRepository(throwOnSave: true);
      final service = AppReleaseNotesService(
        repository: repository,
        remoteSource: _FakeRemoteSource(),
        now: () => now,
        onPersistenceFailure: failures.add,
      );
      final candidate = GiteeReleaseCandidate(
        tag: 'v0.0.6',
        version: version,
        apkUri: Uri.parse('https://example.com/app.apk'),
        checksumUri: Uri.parse('https://example.com/app.apk.sha256'),
        releaseNotes: 'Remembered candidate',
      );

      await service.rememberCandidate(candidate);
      final result = await service.loadCurrent(version);

      expect(failures, hasLength(1));
      expect(result, isA<AppReleaseNotesAvailable>());
      expect(
        (result as AppReleaseNotesAvailable).notes.body,
        'Remembered candidate',
      );
    },
  );
}

AppReleaseNotes _notes(Version version, {required DateTime now}) {
  return AppReleaseNotes(
    version: version,
    tag: 'v$version',
    body: 'Current release',
    fetchedAt: now,
  );
}

final class _FakeRepository implements AppReleaseNotesRepository {
  _FakeRepository({this.throwOnSave = false});

  final bool throwOnSave;
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
    if (throwOnSave) {
      throw StateError('save failed');
    }
    notes[value.version.toString()] = value;
  }
}

final class _FakeRemoteSource implements AppReleaseNotesRemoteSource {
  _FakeRemoteSource({this.result, this.futureResult});

  final AppReleaseNotesLoadResult? result;
  final Future<AppReleaseNotesLoadResult>? futureResult;
  var fetchCount = 0;

  @override
  Future<AppReleaseNotesLoadResult> fetch(Version version) async {
    fetchCount++;
    final pending = futureResult;
    if (pending != null) {
      return pending;
    }
    return result ??
        const AppReleaseNotesUnavailable(
          failure: AppUpdateFailure(
            code: AppUpdateFailureCode.remoteUnavailable,
            message: 'not configured',
          ),
        );
  }
}
