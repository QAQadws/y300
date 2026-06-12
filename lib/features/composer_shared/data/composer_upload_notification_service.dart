import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/data/flutter_local_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_client.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

/// 通过通知栏向用户反馈图片上传进度。
/// 上传是后台行为，UI 侧也有进度条；通知栏只是兜底，所以失败必须降级。
abstract class ComposerUploadNotificationService {
  Future<void> showProgress({
    required int current,
    required int total,
  });

  Future<void> showFailure({
    required int failedCount,
    required int total,
  });

  Future<void> clear();
}

class FlutterLocalComposerUploadNotificationService
    implements ComposerUploadNotificationService {
  FlutterLocalComposerUploadNotificationService({
    LibraryTaskNotificationClient? client,
    Duration failureClearDelay = defaultFailureClearDelay,
  })  : _client = client ??
            FlutterLocalNotificationClient(
              channelId: channelId,
              channelName: channelName,
              channelDescription: channelDescription,
            ),
        _failureClearDelay = failureClearDelay;

  static const int notificationId = 3101;
  // 渠道 ID 沿用 reply_uploads，避免在用户系统通知设置里出现两个权限项；
  // Phase 7 之后回复 / 发帖共用同一个 service，渠道名改成更通用的描述，
  // 用户在系统通知设置里看到的就是"编辑器图片上传"而不是仅限"回复"。
  static const String channelId = 'reply_uploads';
  static const String channelName = '编辑器图片上传';
  static const String channelDescription = '回复 / 发帖页图片上传进度';
  static const Duration defaultFailureClearDelay = Duration(seconds: 2);

  final LibraryTaskNotificationClient _client;
  final Duration _failureClearDelay;
  bool _initialized = false;
  bool _permissionGranted = false;

  @override
  Future<void> showProgress({
    required int current,
    required int total,
  }) async {
    await _showQuietly(
      title: '正在上传回复图片',
      body: '第 ${_clampedProgress(current, total)}/$total 张',
      current: current,
      total: total,
      ongoing: true,
    );
  }

  @override
  Future<void> showFailure({
    required int failedCount,
    required int total,
  }) async {
    await _showQuietly(
      title: '回复图片上传失败',
      body: '有 $failedCount/$total 张图片上传失败',
      current: total,
      total: total,
      ongoing: false,
    );
    await Future<void>.delayed(_failureClearDelay);
    await clear();
  }

  @override
  Future<void> clear() async {
    try {
      if (!_initialized) {
        return;
      }
      await _client.cancel(notificationId);
    } catch (_) {
      // 通知栏只是上传反馈，失败不应影响回复编辑和图片上传。
    }
  }

  Future<void> _showQuietly({
    required String title,
    required String body,
    required int current,
    required int total,
    required bool ongoing,
  }) async {
    try {
      await _ensureReady();
      await _client.show(
        LibraryTaskNotificationClientRequest(
          id: notificationId,
          title: title,
          body: body,
          ongoing: ongoing,
          showProgress: total > 0,
          indeterminate: total <= 0,
          maxProgress: total > 0 ? total : 0,
          progress: total > 0 ? _clampedProgress(current, total) : 0,
        ),
      );
    } catch (_) {
      // Best-effort: 权限、平台或插件异常都不能打断上传主流程。
    }
  }

  Future<void> _ensureReady() async {
    if (!_initialized) {
      await _client.initialize();
      _initialized = true;
    }
    if (_permissionGranted) {
      return;
    }
    final permission = await _client.requestPermission();
    if (!permission.isGranted) {
      throw StateError('Notification permission denied');
    }
    _permissionGranted = true;
  }

  @visibleForTesting
  bool get debugInitialized => _initialized;

  int _clampedProgress(int current, int total) {
    if (total <= 0) {
      return 0;
    }
    return current.clamp(0, total).toInt();
  }
}
