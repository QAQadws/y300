import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes.dart';

abstract interface class AppReleaseNotesRepository {
  Future<AppReleaseNotes?> read(Version version);

  Future<void> save(AppReleaseNotes notes);

  Future<DateTime?> readLastAttempt(Version version);

  Future<void> recordAttempt(Version version, DateTime attemptedAt);
}
