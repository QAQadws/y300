import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_checksum_lookup_result.dart';

abstract interface class AppUpdateChecksumRepository {
  Future<AppUpdateChecksumLookupResult> fetchChecksum(
    AppUpdateArtifact artifact,
  );
}
