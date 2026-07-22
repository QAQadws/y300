import 'package:flutter_test/flutter_test.dart';
import 'package:version/version.dart';
import 'package:y300/features/app_update/data/gitee/persisting_gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_lookup_result.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';
import 'package:y300/features/app_update/domain/repositories/gitee_latest_release_repository.dart';
import 'package:y300/features/app_update/domain/services/app_release_notes_service.dart';

void main() {
  test('successful latest lookup prewarms release notes persistence', () async {
    final version = Version.parse('0.0.7');
    final candidate = GiteeReleaseCandidate(
      tag: 'v0.0.7',
      version: version,
      apkUri: Uri.parse('https://example.com/app.apk'),
      checksumUri: Uri.parse('https://example.com/app.apk.sha256'),
      releaseNotes: 'Next release',
    );
    final notesRepository = _FakeNotesRepository();
    final repository = PersistingGiteeLatestReleaseRepository(
      delegate: _FakeLatestRepository(
        GiteeReleaseLookupSuccess(
          candidate: candidate,
          source: GiteeReleaseLookupSource.network,
        ),
      ),
      releaseNotesService: AppReleaseNotesService(
        repository: notesRepository,
        remoteSource: const _UnusedRemoteSource(),
        now: () => DateTime.utc(2026, 7, 22),
      ),
    );

    final result = await repository.getLatest();

    expect(result, isA<GiteeReleaseLookupSuccess>());
    expect(notesRepository.notes['0.0.7']?.body, 'Next release');
  });

  test('persistence failure does not replace a successful lookup', () async {
    final candidate = GiteeReleaseCandidate(
      tag: 'v0.0.7',
      version: Version.parse('0.0.7'),
      apkUri: Uri.parse('https://example.com/app.apk'),
      checksumUri: Uri.parse('https://example.com/app.apk.sha256'),
      releaseNotes: 'Next release',
    );
    final repository = PersistingGiteeLatestReleaseRepository(
      delegate: _FakeLatestRepository(
        GiteeReleaseLookupSuccess(
          candidate: candidate,
          source: GiteeReleaseLookupSource.network,
        ),
      ),
      releaseNotesService: AppReleaseNotesService(
        repository: _FakeNotesRepository(throwOnSave: true),
        remoteSource: const _UnusedRemoteSource(),
      ),
    );

    expect(await repository.getLatest(), isA<GiteeReleaseLookupSuccess>());
  });
}

final class _FakeLatestRepository implements GiteeLatestReleaseRepository {
  const _FakeLatestRepository(this.result);

  final GiteeReleaseLookupResult result;

  @override
  Future<GiteeReleaseLookupResult> getLatest({
    bool forceRefresh = false,
  }) async {
    return result;
  }
}

final class _FakeNotesRepository implements AppReleaseNotesRepository {
  _FakeNotesRepository({this.throwOnSave = false});

  final bool throwOnSave;
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
    if (throwOnSave) {
      throw StateError('save failed');
    }
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
