import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

sealed class AppUpdateDownloadState {
  const AppUpdateDownloadState();
}

final class AppUpdateIdle extends AppUpdateDownloadState {
  const AppUpdateIdle();
}

final class AppUpdatePreparing extends AppUpdateDownloadState {
  const AppUpdatePreparing(this.artifact);

  final AppUpdateArtifact artifact;
}

final class AppUpdateDownloading extends AppUpdateDownloadState {
  const AppUpdateDownloading({
    required this.artifact,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final AppUpdateArtifact artifact;
  final double progress;
  final int receivedBytes;
  final int? totalBytes;
}

final class AppUpdateVerifying extends AppUpdateDownloadState {
  const AppUpdateVerifying(this.artifact);

  final AppUpdateArtifact artifact;
}

final class AppUpdateReadyToInstall extends AppUpdateDownloadState {
  const AppUpdateReadyToInstall({
    required this.artifact,
    required this.apkPath,
  });

  final AppUpdateArtifact artifact;
  final String apkPath;
}

/// The system installer has been opened. Android still owns the final
/// confirmation and Y300 must not report the update as installed yet.
final class AppUpdateInstalling extends AppUpdateDownloadState {
  const AppUpdateInstalling({required this.artifact, required this.apkPath});

  final AppUpdateArtifact artifact;
  final String apkPath;
}

final class AppUpdateFailed extends AppUpdateDownloadState {
  const AppUpdateFailed({this.artifact, required this.failure});

  final AppUpdateArtifact? artifact;
  final AppUpdateFailure failure;
}
