import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/services/library_task_notification_service_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

/// Shared system-notification service for long-running library tasks.
///
/// Kept in the shared workflow layer so favorites/comic features consume the
/// same instance. Stage 4 adds the progress-to-notification bridge on top; this
/// provider only exposes the capability and its lifecycle.
final libraryTaskNotificationServiceProvider =
    Provider<LibraryTaskNotificationService>((ref) {
      final service = FlutterLocalLibraryTaskNotificationService();
      ref.onDispose(service.disposeIfNeeded);
      return service;
    });
