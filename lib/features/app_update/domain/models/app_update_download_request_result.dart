import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateDownloadRequestResult {
  const AppUpdateDownloadRequestResult();
}

final class AppUpdateDownloadRequestAccepted
    extends AppUpdateDownloadRequestResult {
  const AppUpdateDownloadRequestAccepted(this.artifact);

  final AppUpdateArtifact artifact;
}

final class AppUpdateDownloadRequestFailure
    extends AppUpdateDownloadRequestResult {
  const AppUpdateDownloadRequestFailure(this.failure);

  final AppUpdateFailure failure;
}
