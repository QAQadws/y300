import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_task.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_notification_tap.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';

/// Optional background capability owned by the platform adapter.
///
/// The application service and UI depend on these Y300 contracts rather than
/// on background_downloader's task enums or persistent-storage classes.
abstract interface class AppUpdateBackgroundBinaryDownloader
    implements AppUpdateBinaryDownloader {
  Stream<AppUpdateBackgroundNotificationTap> get notificationTapStream;

  Future<void> initialize();

  Future<List<AppUpdateBackgroundTaskSnapshot>> recover();

  Future<bool> hasRecoverableTask(AppUpdateArtifactIdentity identity);

  /// Drops the plugin task record after the user explicitly discards the
  /// update. The service only calls this when no transfer is active.
  Future<void> discard(AppUpdateArtifactIdentity identity);
}
