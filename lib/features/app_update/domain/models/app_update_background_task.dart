import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

enum AppUpdateBackgroundTaskStatus {
  enqueued,
  running,
  paused,
  waitingToRetry,
  complete,
  failed,
  canceled,
  notFound,
}

final class AppUpdateBackgroundTaskSnapshot {
  const AppUpdateBackgroundTaskSnapshot({
    required this.taskId,
    required this.artifact,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    this.progress = 0,
    this.failure,
  });

  final String taskId;
  final AppUpdateArtifact artifact;
  final AppUpdateBackgroundTaskStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final double progress;
  final AppUpdateFailure? failure;

  AppUpdateArtifactIdentity get identity => artifact.identity;
}
