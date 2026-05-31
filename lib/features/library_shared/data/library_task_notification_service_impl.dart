import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/data/flutter_local_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

/// Default [LibraryTaskNotificationService].
///
/// Owns the channel identity, the key -> Android notification id mapping and
/// the progress-style decision, then delegates the actual platform call to a
/// [LibraryTaskNotificationClient]. The client seam keeps this class unit
/// testable without a real `flutter_local_notifications` channel.
class FlutterLocalLibraryTaskNotificationService
    implements LibraryTaskNotificationService {
  FlutterLocalLibraryTaskNotificationService({
    LibraryTaskNotificationClient? client,
  }) : _client = client ?? FlutterLocalNotificationClient();

  final LibraryTaskNotificationClient _client;

  // Android channel config (shared by both task notifications).
  static const String channelId = 'library_tasks';
  static const String channelName = '书架任务';
  static const String channelDescription = '收藏同步与漫画搜索等待进度';

  // Fixed Android notification ids so repeated updates replace, not stack.
  static const int favoriteSyncNotificationId = 3001;
  static const int comicSearchQueueNotificationId = 3002;

  bool _initialized = false;
  LibraryTaskNotificationPermissionState? _permissionState;

  static int notificationIdFor(LibraryTaskNotificationKey key) {
    return switch (key) {
      LibraryTaskNotificationKey.favoriteSync => favoriteSyncNotificationId,
      LibraryTaskNotificationKey.comicSearchQueue =>
        comicSearchQueueNotificationId,
    };
  }

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _client.initialize();
    _initialized = true;
  }

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    await initialize();
    if (_permissionState?.isGranted == true) {
      return _permissionState!;
    }
    final state = await _client.requestPermission();
    _permissionState = state;
    return state;
  }

  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {
    final permission = await ensurePermission();
    // Permission failure must never break the underlying task: just skip the
    // OS notification and let the in-app banner fallback (stage 5) take over.
    if (!permission.isGranted) {
      return;
    }

    final hasProgress = notification.hasDeterminateProgress;
    await _client.show(
      LibraryTaskNotificationClientRequest(
        id: notificationIdFor(notification.key),
        title: notification.title,
        body: notification.body,
        ongoing: notification.ongoing,
        // Always render a progress bar for ongoing tasks; without an explicit
        // total it becomes indeterminate.
        showProgress: true,
        indeterminate: !hasProgress,
        maxProgress: hasProgress ? notification.total! : 0,
        progress: hasProgress ? notification.current! : 0,
      ),
    );
  }

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {
    if (!_initialized) {
      // Nothing could have been shown yet.
      return;
    }
    await _client.cancel(notificationIdFor(key));
  }

  /// Provider disposal hook. The plugin has no explicit teardown, so this only
  /// resets cached state; kept as a named method so providers can wire it.
  void disposeIfNeeded() {
    _initialized = false;
    _permissionState = null;
  }

  @visibleForTesting
  LibraryTaskNotificationPermissionState? get debugPermissionState =>
      _permissionState;
}
