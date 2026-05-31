import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

/// Platform-neutral request handed to a [LibraryTaskNotificationClient].
///
/// The service resolves the notification key to a fixed id and decides the
/// progress style *before* calling the client, so the plugin wrapper stays
/// dumb and the mapping logic can be asserted with a fake client.
class LibraryTaskNotificationClientRequest {
  const LibraryTaskNotificationClientRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.ongoing,
    required this.showProgress,
    required this.indeterminate,
    required this.maxProgress,
    required this.progress,
  });

  final int id;
  final String title;
  final String body;
  final bool ongoing;
  final bool showProgress;
  final bool indeterminate;
  final int maxProgress;
  final int progress;
}

/// Thin seam over the actual notification plugin.
///
/// Everything platform-specific (`flutter_local_notifications`,
/// `permission_handler`) lives behind this port so
/// [LibraryTaskNotificationService] logic can be unit tested without real
/// channels. See `library_task_notification_service_impl.dart` for the default
/// `flutter_local_notifications`-backed implementation.
abstract class LibraryTaskNotificationClient {
  /// Prepares the platform channel. Idempotent.
  Future<void> initialize();

  /// Requests/re-checks the OS notification permission.
  Future<LibraryTaskNotificationPermissionState> requestPermission();

  /// Posts or replaces the notification described by [request].
  Future<void> show(LibraryTaskNotificationClientRequest request);

  /// Cancels the notification with [id].
  Future<void> cancel(int id);
}
