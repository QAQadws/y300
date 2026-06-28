import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/data/services/flutter_local_notification_client.dart';
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
    Duration timeout = defaultTimeout,
    Duration heartbeatInterval = defaultHeartbeatInterval,
  })  : _client = client ?? FlutterLocalNotificationClient(),
        _timeout = timeout,
        _heartbeatInterval = heartbeatInterval;

  final LibraryTaskNotificationClient _client;

  // A posted notification outlives the Dart isolate, so killing the app would
  // otherwise leave an "ongoing" notification stuck. We post it with an Android
  // timeoutAfter and refresh it on a heartbeat while the process is alive: once
  // the app dies the refresh stops and Android clears it within [_timeout].
  final Duration _timeout;
  final Duration _heartbeatInterval;

  // Slow favorite-sync steps can hold one message for up to the network receive
  // timeout (~20s) and a waiting comic queue refreshes every ~10.5s, so the
  // timeout must comfortably exceed both to avoid a mid-task flicker.
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration defaultHeartbeatInterval = Duration(seconds: 8);

  // Android channel config (shared by both task notifications).
  static const String channelId = 'library_tasks';
  static const String channelName = '书架任务';
  static const String channelDescription = '收藏同步与漫画搜索等待进度';

  // Fixed Android notification ids so repeated updates replace, not stack.
  static const int favoriteSyncNotificationId = 3001;
  static const int comicSearchQueueNotificationId = 3002;

  bool _initialized = false;
  final ValueNotifier<LibraryTaskNotificationPermissionState?>
      _permissionStateNotifier =
      ValueNotifier<LibraryTaskNotificationPermissionState?>(null);

  // Last notification posted per key, kept so the heartbeat can re-post the
  // unchanged content and reset the Android timeout window.
  final Map<LibraryTaskNotificationKey, LibraryTaskNotification> _active =
      <LibraryTaskNotificationKey, LibraryTaskNotification>{};
  Timer? _heartbeatTimer;

  static int notificationIdFor(LibraryTaskNotificationKey key) {
    return switch (key) {
      LibraryTaskNotificationKey.favoriteSync => favoriteSyncNotificationId,
      LibraryTaskNotificationKey.comicSearchQueue =>
        comicSearchQueueNotificationId,
    };
  }

  @override
  ValueListenable<LibraryTaskNotificationPermissionState?> get permissionState =>
      _permissionStateNotifier;

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
    final current = _permissionStateNotifier.value;
    if (current?.isGranted == true) {
      return current!;
    }
    final state = await _client.requestPermission();
    _permissionStateNotifier.value = state;
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

    _active[notification.key] = notification;
    _ensureHeartbeat();
    await _post(notification);
  }

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {
    _active.remove(key);
    if (_active.isEmpty) {
      _stopHeartbeat();
    }
    if (!_initialized) {
      // Nothing could have been shown yet.
      return;
    }
    await _client.cancel(notificationIdFor(key));
  }

  Future<void> _post(LibraryTaskNotification notification) async {
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
        timeoutAfterMs: _timeout.inMilliseconds,
      ),
    );
  }

  void _ensureHeartbeat() {
    _heartbeatTimer ??= Timer.periodic(_heartbeatInterval, (_) {
      // Re-post active notifications so the Android timeoutAfter window keeps
      // sliding while the app is alive. After the process is killed this timer
      // stops firing and the OS clears the notifications on its own.
      for (final notification in _active.values) {
        unawaited(_post(notification));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Provider disposal hook. Stops the heartbeat and resets cached state.
  void disposeIfNeeded() {
    _stopHeartbeat();
    _active.clear();
    _initialized = false;
    _permissionStateNotifier.value = null;
  }

  @visibleForTesting
  LibraryTaskNotificationPermissionState? get debugPermissionState =>
      _permissionStateNotifier.value;
}
