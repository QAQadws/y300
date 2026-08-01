import 'package:flutter/foundation.dart';

/// Stable identity for each long-running library task that can surface a
/// system notification. The key also maps to a fixed Android notification id so
/// repeated updates replace the same notification instead of stacking.
enum LibraryTaskNotificationKey { favoriteSync, comicSearchQueue }

/// Result of requesting/checking the OS notification permission.
///
/// `permanentlyDenied` lets the presentation layer (stage 5) decide whether to
/// keep the in-app banner fallback instead of silently losing task feedback.
enum LibraryTaskNotificationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unsupported,
}

extension LibraryTaskNotificationPermissionStateX
    on LibraryTaskNotificationPermissionState {
  bool get isGranted => this == LibraryTaskNotificationPermissionState.granted;
}

/// A single progress notification request.
///
/// `current`/`total` are optional: when both are present the default
/// implementation renders a determinate progress bar, otherwise it falls back
/// to an indeterminate one. `ongoing` keeps the notification non-dismissible
/// while the task is still running.
class LibraryTaskNotification {
  const LibraryTaskNotification({
    required this.key,
    required this.title,
    required this.body,
    this.current,
    this.total,
    this.ongoing = true,
  });

  final LibraryTaskNotificationKey key;
  final String title;
  final String body;
  final int? current;
  final int? total;
  final bool ongoing;

  bool get hasDeterminateProgress =>
      total != null && total! > 0 && current != null;
}

/// Shared system-notification capability for long-running library tasks.
///
/// This stays a thin presentation adapter: it knows how to show/clear OS
/// notifications but nothing about how favorites sync or comic search work.
/// Stage 4 feeds it from `LibraryTaskProgressHub`.
abstract class LibraryTaskNotificationService {
  /// Prepares platform channels. Safe to call more than once.
  Future<void> initialize();

  /// Last known OS notification permission state.
  ///
  /// `null` means the app has not checked yet, so presentation should keep the
  /// in-app banner fallback visible.
  ValueListenable<LibraryTaskNotificationPermissionState?> get permissionState;

  /// Requests (or re-checks) the OS notification permission.
  Future<LibraryTaskNotificationPermissionState> ensurePermission();

  /// Shows a new notification or updates the existing one for the same key.
  Future<void> showOrUpdate(LibraryTaskNotification notification);

  /// Removes the notification for [key] (task completed/failed/idle).
  Future<void> clear(LibraryTaskNotificationKey key);
}
