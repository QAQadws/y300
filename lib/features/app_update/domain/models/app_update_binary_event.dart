import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';

enum AppUpdateBinaryEventType {
  started,
  progress,
  completed,
  cancelled,
  failed,
}

/// Transport events owned by Y300 rather than by Dio or a future background
/// download plugin.
final class AppUpdateBinaryEvent {
  const AppUpdateBinaryEvent({
    required this.identity,
    required this.type,
    required this.receivedBytes,
    required this.totalBytes,
    required this.progress,
    this.failure,
  });

  factory AppUpdateBinaryEvent.started(AppUpdateArtifactIdentity identity) {
    return AppUpdateBinaryEvent(
      identity: identity,
      type: AppUpdateBinaryEventType.started,
      receivedBytes: 0,
      totalBytes: null,
      progress: 0,
    );
  }

  factory AppUpdateBinaryEvent.progress({
    required AppUpdateArtifactIdentity identity,
    required int receivedBytes,
    required int? totalBytes,
    double? reportedProgress,
  }) {
    return AppUpdateBinaryEvent(
      identity: identity,
      type: AppUpdateBinaryEventType.progress,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      progress: _progress(receivedBytes, totalBytes, reportedProgress),
    );
  }

  factory AppUpdateBinaryEvent.completed({
    required AppUpdateArtifactIdentity identity,
    required int receivedBytes,
    required int? totalBytes,
  }) {
    return AppUpdateBinaryEvent(
      identity: identity,
      type: AppUpdateBinaryEventType.completed,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      progress: 1,
    );
  }

  factory AppUpdateBinaryEvent.cancelled({
    required AppUpdateArtifactIdentity identity,
    required int receivedBytes,
    required int? totalBytes,
  }) {
    return AppUpdateBinaryEvent(
      identity: identity,
      type: AppUpdateBinaryEventType.cancelled,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      progress: _progress(receivedBytes, totalBytes, null),
      failure: const AppUpdateFailure(
        code: AppUpdateFailureCode.apkDownloadCancelled,
        message: 'The update download was cancelled.',
      ),
    );
  }

  factory AppUpdateBinaryEvent.failed({
    required AppUpdateArtifactIdentity identity,
    required int receivedBytes,
    required int? totalBytes,
    required AppUpdateFailure failure,
  }) {
    return AppUpdateBinaryEvent(
      identity: identity,
      type: AppUpdateBinaryEventType.failed,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      progress: _progress(receivedBytes, totalBytes, null),
      failure: failure,
    );
  }

  final AppUpdateArtifactIdentity identity;
  final AppUpdateBinaryEventType type;
  final int receivedBytes;
  final int? totalBytes;
  final double progress;
  final AppUpdateFailure? failure;

  static double _progress(
    int receivedBytes,
    int? totalBytes,
    double? reportedProgress,
  ) {
    if (reportedProgress != null && reportedProgress.isFinite) {
      return reportedProgress.clamp(0, 1).toDouble();
    }
    if (totalBytes == null || totalBytes <= 0) {
      return 0;
    }
    final value = receivedBytes / totalBytes;
    return value.clamp(0, 1).toDouble();
  }
}
