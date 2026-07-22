import 'package:y300/features/app_update/domain/models/app_release_notes.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppReleaseNotesLoadResult {
  const AppReleaseNotesLoadResult();
}

final class AppReleaseNotesAvailable extends AppReleaseNotesLoadResult {
  const AppReleaseNotesAvailable(this.notes);

  final AppReleaseNotes notes;
}

final class AppReleaseNotesUnavailable extends AppReleaseNotesLoadResult {
  const AppReleaseNotesUnavailable({
    required this.failure,
    this.retryDeferred = false,
  });

  final AppUpdateFailure failure;
  final bool retryDeferred;
}
