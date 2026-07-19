import 'package:y300/features/app_update/domain/models/app_update_checksum.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateChecksumLookupResult {
  const AppUpdateChecksumLookupResult();
}

final class AppUpdateChecksumLookupSuccess
    extends AppUpdateChecksumLookupResult {
  const AppUpdateChecksumLookupSuccess(this.checksum);

  final AppUpdateChecksum checksum;
}

final class AppUpdateChecksumLookupFailure
    extends AppUpdateChecksumLookupResult {
  const AppUpdateChecksumLookupFailure(this.failure);

  final AppUpdateFailure failure;
}
