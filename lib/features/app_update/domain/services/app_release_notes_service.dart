import 'dart:async';

import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_remote_source.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';

typedef AppReleaseNotesFailureReporter = void Function(Object error);

final class AppReleaseNotesService {
  AppReleaseNotesService({
    required AppReleaseNotesRepository repository,
    required AppReleaseNotesRemoteSource remoteSource,
    DateTime Function()? now,
    this.failureBackoff = defaultFailureBackoff,
    AppReleaseNotesFailureReporter? onPersistenceFailure,
  }) : _repository = repository,
       _remoteSource = remoteSource,
       _now = now ?? DateTime.now,
       _onPersistenceFailure = onPersistenceFailure;

  static const Duration defaultFailureBackoff = Duration(hours: 6);

  final AppReleaseNotesRepository _repository;
  final AppReleaseNotesRemoteSource _remoteSource;
  final DateTime Function() _now;
  final Duration failureBackoff;
  final AppReleaseNotesFailureReporter? _onPersistenceFailure;

  final Map<String, AppReleaseNotes> _sessionNotes =
      <String, AppReleaseNotes>{};
  final Map<String, DateTime> _sessionAttempts = <String, DateTime>{};
  final Map<String, Future<AppReleaseNotesLoadResult>> _inFlight =
      <String, Future<AppReleaseNotesLoadResult>>{};

  Future<AppReleaseNotesLoadResult> loadCurrent(
    Version installedVersion, {
    bool forceRefresh = false,
  }) {
    final key = installedVersion.toString();
    final sessionNotes = _sessionNotes[key];
    if (sessionNotes != null) {
      return Future<AppReleaseNotesLoadResult>.value(
        AppReleaseNotesAvailable(sessionNotes),
      );
    }
    final current = _inFlight[key];
    if (current != null) {
      return current;
    }

    final request = _loadCurrent(installedVersion, forceRefresh: forceRefresh);
    _inFlight[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    });
  }

  Future<AppReleaseNotesLoadResult> _loadCurrent(
    Version installedVersion, {
    required bool forceRefresh,
  }) async {
    final key = installedVersion.toString();
    final persisted = await _readPersisted(installedVersion);
    if (persisted != null) {
      _sessionNotes[key] = persisted;
      return AppReleaseNotesAvailable(persisted);
    }

    if (!forceRefresh) {
      final attemptedAt =
          _sessionAttempts[key] ?? await _readLastAttempt(installedVersion);
      if (_isBackoffActive(attemptedAt)) {
        return const AppReleaseNotesUnavailable(
          failure: AppUpdateFailure(
            code: AppUpdateFailureCode.rateLimited,
            message: 'Release notes retry is deferred after a recent failure.',
          ),
          retryDeferred: true,
        );
      }
    }

    return _fetchAndRemember(installedVersion);
  }

  Future<void> rememberCandidate(GiteeReleaseCandidate candidate) async {
    final key = candidate.version.toString();
    final body = candidate.releaseNotes ?? '';
    final existing =
        _sessionNotes[key] ?? await _readPersisted(candidate.version);
    if (existing != null &&
        existing.tag == candidate.tag &&
        existing.body == body) {
      _sessionNotes[key] = existing;
      return;
    }

    final notes = AppReleaseNotes(
      version: candidate.version,
      tag: candidate.tag,
      body: body,
      fetchedAt: _now().toUtc(),
    );
    _sessionNotes[key] = notes;
    await _saveBestEffort(notes);
  }

  Future<AppReleaseNotesLoadResult> _fetchAndRemember(Version version) async {
    final key = version.toString();
    final attemptedAt = _now().toUtc();
    _sessionAttempts[key] = attemptedAt;
    await _recordAttemptBestEffort(version, attemptedAt);

    late final AppReleaseNotesLoadResult result;
    try {
      result = await _remoteSource.fetch(version);
    } on Object {
      return const AppReleaseNotesUnavailable(
        failure: AppUpdateFailure(
          code: AppUpdateFailureCode.remoteUnavailable,
          message: 'Fetching release notes failed unexpectedly.',
        ),
      );
    }
    if (result case AppReleaseNotesAvailable(:final notes)) {
      _sessionNotes[key] = notes;
      await _saveBestEffort(notes);
    }
    return result;
  }

  Future<AppReleaseNotes?> _readPersisted(Version version) async {
    try {
      return await _repository.read(version);
    } on Object catch (error) {
      _reportPersistenceFailure(error);
      return null;
    }
  }

  Future<DateTime?> _readLastAttempt(Version version) async {
    try {
      final attemptedAt = await _repository.readLastAttempt(version);
      if (attemptedAt != null) {
        _sessionAttempts[version.toString()] = attemptedAt;
      }
      return attemptedAt;
    } on Object catch (error) {
      _reportPersistenceFailure(error);
      return null;
    }
  }

  Future<void> _saveBestEffort(AppReleaseNotes notes) async {
    try {
      await _repository.save(notes);
    } on Object catch (error) {
      _reportPersistenceFailure(error);
    }
  }

  Future<void> _recordAttemptBestEffort(
    Version version,
    DateTime attemptedAt,
  ) async {
    try {
      await _repository.recordAttempt(version, attemptedAt);
    } on Object catch (error) {
      _reportPersistenceFailure(error);
    }
  }

  bool _isBackoffActive(DateTime? attemptedAt) {
    if (attemptedAt == null) {
      return false;
    }
    final age = _now().toUtc().difference(attemptedAt.toUtc());
    return !age.isNegative && age < failureBackoff;
  }

  void _reportPersistenceFailure(Object error) {
    _onPersistenceFailure?.call(error);
  }
}
