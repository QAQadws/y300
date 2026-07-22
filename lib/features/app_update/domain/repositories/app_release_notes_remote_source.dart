import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_release_notes_load_result.dart';

abstract interface class AppReleaseNotesRemoteSource {
  Future<AppReleaseNotesLoadResult> fetch(Version version);
}
