import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:y300/features/library_shared/data/services/library_task_notification_service_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

/// Default [LibraryTaskNotificationClient] backed by
/// `flutter_local_notifications` + `permission_handler`.
///
/// All plugin types are confined to this file so the rest of the notification
/// stack stays platform agnostic and unit testable.
class FlutterLocalNotificationClient implements LibraryTaskNotificationClient {
  FlutterLocalNotificationClient({
    FlutterLocalNotificationsPlugin? plugin,
    String channelId = FlutterLocalLibraryTaskNotificationService.channelId,
    String channelName = FlutterLocalLibraryTaskNotificationService.channelName,
    String channelDescription =
        FlutterLocalLibraryTaskNotificationService.channelDescription,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _channelId = channelId,
        _channelName = channelName,
        _channelDescription = channelDescription;

  final FlutterLocalNotificationsPlugin _plugin;
  final String _channelId;
  final String _channelName;
  final String _channelDescription;
  final Set<String> _createdChannelIds = <String>{};

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS permission is requested explicitly later via [requestPermission] so
    // initialization stays quiet on first launch.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );
    await _ensureAndroidChannel();
  }

  Future<void> _ensureAndroidChannel() async {
    if (_createdChannelIds.contains(_channelId) ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return;
    }
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    _createdChannelIds.add(_channelId);
  }

  @override
  Future<LibraryTaskNotificationPermissionState> requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _requestAndroidPermission();
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _requestDarwinPermission();
      default:
        return LibraryTaskNotificationPermissionState.unsupported;
    }
  }

  Future<LibraryTaskNotificationPermissionState>
      _requestAndroidPermission() async {
    // POST_NOTIFICATIONS only gates Android 13+; older versions report granted.
    final status = await Permission.notification.request();
    if (status.isGranted) {
      return LibraryTaskNotificationPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return LibraryTaskNotificationPermissionState.permanentlyDenied;
    }
    return LibraryTaskNotificationPermissionState.denied;
  }

  Future<LibraryTaskNotificationPermissionState>
      _requestDarwinPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final granted = await ios?.requestPermissions(
      alert: true,
      badge: false,
      sound: false,
    );
    return (granted ?? false)
        ? LibraryTaskNotificationPermissionState.granted
        : LibraryTaskNotificationPermissionState.denied;
  }

  @override
  Future<void> show(LibraryTaskNotificationClientRequest request) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: request.ongoing,
      autoCancel: !request.ongoing,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showProgress: request.showProgress,
      indeterminate: request.indeterminate,
      maxProgress: request.maxProgress,
      progress: request.progress,
      // Auto-cancel if not refreshed in time, so the notification clears itself
      // once the app process is killed and can no longer cancel it explicitly.
      timeoutAfter: request.timeoutAfterMs,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentSound: false,
      presentBadge: false,
    );
    await _plugin.show(
      id: request.id,
      title: request.title,
      body: request.body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
    );
  }

  @override
  Future<void> cancel(int id) {
    return _plugin.cancel(id: id);
  }
}
