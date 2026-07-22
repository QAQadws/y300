import 'dart:async';

import 'package:version/version.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/app_update/data/local/app_release_notes_snapshot_codec.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/repositories/app_release_notes_repository.dart';

final class SharedPrefsAppReleaseNotesRepository
    implements AppReleaseNotesRepository {
  SharedPrefsAppReleaseNotesRepository({
    required PreferencesStore preferencesStore,
  }) : _preferencesStore = preferencesStore;

  final PreferencesStore _preferencesStore;
  Future<void> _pendingMutation = Future<void>.value();

  @override
  Future<AppReleaseNotes?> read(Version version) async {
    await _pendingMutation;
    return (await _readSnapshot()).notesByVersion[version.toString()];
  }

  @override
  Future<DateTime?> readLastAttempt(Version version) async {
    await _pendingMutation;
    return (await _readSnapshot()).attemptsByVersion[version.toString()];
  }

  @override
  Future<void> recordAttempt(Version version, DateTime attemptedAt) {
    return _mutate((snapshot) {
      snapshot.attemptsByVersion[version.toString()] = attemptedAt.toUtc();
    });
  }

  @override
  Future<void> save(AppReleaseNotes notes) {
    return _mutate((snapshot) {
      snapshot.notesByVersion[notes.version.toString()] = notes;
    });
  }

  Future<AppReleaseNotesSnapshot> _readSnapshot() async {
    final raw = await _preferencesStore.read(
      PreferenceKeys.appUpdateReleaseNotesSnapshotV1,
    );
    return AppReleaseNotesSnapshotCodec.decode(raw);
  }

  Future<void> _mutate(
    void Function(AppReleaseNotesSnapshot snapshot) mutation,
  ) {
    final operation = _pendingMutation.then((_) async {
      final snapshot = await _readSnapshot();
      mutation(snapshot);
      await _preferencesStore.write(
        PreferenceKeys.appUpdateReleaseNotesSnapshotV1,
        AppReleaseNotesSnapshotCodec.encode(snapshot),
      );
    });
    _pendingMutation = operation.catchError((_) {});
    return operation;
  }
}
