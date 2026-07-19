import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';

/// A user tap on an update notification, without exposing the downloader
/// plugin's task or notification types to the domain layer.
final class AppUpdateBackgroundNotificationTap {
  const AppUpdateBackgroundNotificationTap({required this.identity});

  final AppUpdateArtifactIdentity identity;
}
