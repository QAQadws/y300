import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:version/version.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_notification_tap.dart';
import 'package:y300/features/app_update/domain/models/app_update_background_task.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/models/gitee_release_candidate.dart';
import 'package:y300/features/app_update/domain/services/app_update_background_binary_downloader.dart';

/// Platform adapter for background_downloader's central task database and
/// notification owner.
///
/// The plugin is intentionally contained in this file. The rest of app_update
/// only sees Y300 artifacts, snapshots and binary events.
final class BackgroundDownloaderBinaryDownloader
    implements AppUpdateBackgroundBinaryDownloader {
  BackgroundDownloaderBinaryDownloader({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader() {
    _instances.add(this);
  }

  static const String taskGroup = 'y300_app_update';
  static const String _stagingDirectory = 'updates/staging';
  static final Set<BackgroundDownloaderBinaryDownloader> _instances =
      <BackgroundDownloaderBinaryDownloader>{};
  static StreamSubscription<TaskUpdate>? _sharedUpdatesSubscription;
  static Future<void>? _sharedInitialization;

  final FileDownloader _downloader;
  final Map<String, _BackgroundDownloadOperation> _operations =
      <String, _BackgroundDownloadOperation>{};
  final Map<String, _ProgressSnapshot> _progress =
      <String, _ProgressSnapshot>{};
  final StreamController<AppUpdateBackgroundNotificationTap>
  _notificationTapController =
      StreamController<AppUpdateBackgroundNotificationTap>.broadcast();
  Future<void>? _initializeInFlight;
  bool _disposed = false;

  @override
  Stream<AppUpdateBackgroundNotificationTap> get notificationTapStream =>
      _notificationTapController.stream;

  @override
  Stream<AppUpdateBinaryEvent> download(
    AppUpdateArtifact artifact, {
    required String stagingPath,
  }) {
    final taskId = _taskId(artifact.identity);
    final existing = _operations[taskId];
    if (existing != null) {
      return existing.stream;
    }

    final operation = _BackgroundDownloadOperation(
      artifact.identity,
      onFinished: () => _operations.remove(taskId),
    );
    _operations[taskId] = operation;
    scheduleMicrotask(() => _attachOrEnqueue(operation, artifact, stagingPath));
    return operation.stream;
  }

  @override
  Future<void> cancel() async {
    final taskId = _operations.keys.firstOrNull;
    if (taskId == null) {
      return;
    }
    await initialize();
    await _downloader.cancelTaskWithId(taskId);
  }

  @override
  Future<void> initialize() {
    final existing = _initializeInFlight;
    if (existing != null) {
      return existing;
    }
    final initialization = _initialize();
    _initializeInFlight = initialization;
    unawaited(
      initialization.then<void>(
        (_) {
          if (identical(_initializeInFlight, initialization)) {
            _initializeInFlight = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_initializeInFlight, initialization)) {
            _initializeInFlight = null;
          }
        },
      ),
    );
    return initialization;
  }

  @override
  Future<bool> hasRecoverableTask(AppUpdateArtifactIdentity identity) async {
    await initialize();
    final record = await _downloader.database.recordForId(_taskId(identity));
    if (record == null || record.task.group != taskGroup) {
      return false;
    }
    switch (record.status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
        return true;
      case TaskStatus.paused:
        return false;
      case TaskStatus.complete:
        try {
          return File(await record.task.filePath()).existsSync();
        } on Object {
          return false;
        }
      case TaskStatus.notFound:
      case TaskStatus.failed:
      case TaskStatus.canceled:
        return false;
    }
  }

  @override
  Future<void> discard(AppUpdateArtifactIdentity identity) async {
    await initialize();
    // The service calls discard only after the transfer is no longer busy.
    // Removing the record here prevents a completed task from shadowing a
    // later retry after its staging file was promoted or explicitly deleted.
    final taskId = _taskId(identity);
    await _downloader.database.deleteRecordWithId(taskId);
    _progress.remove(taskId);
  }

  @override
  Future<List<AppUpdateBackgroundTaskSnapshot>> recover() async {
    await initialize();
    final records = await _downloader.database.allRecords(group: taskGroup);
    final snapshots = <AppUpdateBackgroundTaskSnapshot>[];
    for (final record in records) {
      final task = record.task;
      final artifact = _artifactFromMetadata(task.metaData);
      if (artifact == null || task is! DownloadTask) {
        await _downloader.database.deleteRecordWithId(record.taskId);
        continue;
      }
      final progress = _progressFromRecord(record);
      snapshots.add(
        AppUpdateBackgroundTaskSnapshot(
          taskId: record.taskId,
          artifact: artifact,
          status: _mapStatus(record.status),
          receivedBytes: progress.receivedBytes,
          totalBytes: progress.totalBytes,
          progress: progress.progress,
          failure: _failureFromRecord(record),
        ),
      );
    }
    return snapshots;
  }

  Future<void> dispose() async {
    _disposed = true;
    _instances.remove(this);
    await _notificationTapController.close();
  }

  Future<void> _initialize() async {
    // background_downloader exposes a single-subscription stream. Keep one
    // process-level listener and fan updates out to live adapter instances.
    _sharedUpdatesSubscription ??= _downloader.updates.listen(
      _dispatchSharedUpdate,
    );
    final existing = _sharedInitialization;
    if (existing != null) {
      await existing;
      return;
    }
    final initialization = _startSharedDownloader(_downloader);
    _sharedInitialization = initialization;
    await initialization;
  }

  static void _dispatchSharedUpdate(TaskUpdate update) {
    for (final instance in _instances.toList(growable: false)) {
      if (!instance._disposed) {
        instance._handleUpdate(update);
      }
    }
  }

  Future<void> _startSharedDownloader(FileDownloader downloader) async {
    downloader.configureNotificationForGroup(
      taskGroup,
      running: const TaskNotification('Y300 更新', '正在下载 {progress}'),
      complete: const TaskNotification('Y300 更新', '下载完成，返回应用继续校验'),
      error: const TaskNotification('Y300 更新', '下载失败，可返回应用重试'),
      canceled: const TaskNotification('Y300 更新', '下载已取消'),
      progressBar: true,
      tapOpensFile: false,
    );
    downloader.registerCallbacks(
      group: taskGroup,
      taskNotificationTapCallback: _handleNotificationTap,
    );
    await downloader.configure(
      androidConfig: const <(String, dynamic)>[
        (Config.runInForeground, Config.always),
      ],
    );
    await _requestNotificationPermissionBestEffort(downloader);
    await downloader.start(autoCleanDatabase: true);
  }

  void _handleNotificationTap(Task task, NotificationType _) {
    if (_disposed || task.group != taskGroup) {
      return;
    }
    final artifact = _artifactFromMetadata(task.metaData);
    if (artifact == null || _notificationTapController.isClosed) {
      return;
    }
    _notificationTapController.add(
      AppUpdateBackgroundNotificationTap(identity: artifact.identity),
    );
  }

  Future<void> _requestNotificationPermissionBestEffort(
    FileDownloader downloader,
  ) async {
    try {
      final status = await downloader.permissions.status(
        PermissionType.notifications,
      );
      if (status == PermissionStatus.undetermined) {
        await downloader.permissions.request(PermissionType.notifications);
      }
    } on Object {
      // Notifications are optional. AppUpdateDownloadService remains the
      // source of truth when Android or the user declines this permission.
    }
  }

  Future<void> _attachOrEnqueue(
    _BackgroundDownloadOperation operation,
    AppUpdateArtifact artifact,
    String stagingPath,
  ) async {
    try {
      if (_disposed) {
        _finishWithFailure(
          operation,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'The background update downloader has been disposed.',
          ),
        );
        return;
      }
      await initialize();
      final task = await _taskForArtifact(artifact);
      if (task != null) {
        if (!_samePath(await task.filePath(), stagingPath)) {
          _finishWithFailure(
            operation,
            const AppUpdateFailure(
              code: AppUpdateFailureCode.apkDownloadStartFailed,
              message: 'The background task path is outside update staging.',
            ),
          );
          return;
        }
        final record = await _downloader.database.recordForId(task.taskId);
        final canReuseCompletedTask =
            record?.status == TaskStatus.complete &&
            File(await task.filePath()).existsSync();
        if (record != null &&
            (canReuseCompletedTask ||
                record.status == TaskStatus.enqueued ||
                record.status == TaskStatus.running ||
                record.status == TaskStatus.waitingToRetry)) {
          await _emitRecord(operation, record);
          return;
        }
        await _downloader.database.deleteRecordWithId(task.taskId);
      }

      final newTask = DownloadTask(
        taskId: _taskId(artifact.identity),
        url: artifact.apkUri.toString(),
        filename: artifact.identity.stagingFileName,
        directory: _stagingDirectory,
        baseDirectory: BaseDirectory.applicationSupport,
        group: taskGroup,
        updates: Updates.statusAndProgress,
        retries: 2,
        allowPause: false,
        metaData: jsonEncode(_metadataFor(artifact)),
        displayName: 'Y300 v${artifact.version}',
      );
      if (!_samePath(await newTask.filePath(), stagingPath)) {
        _finishWithFailure(
          operation,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'The background task path does not match staging.',
          ),
        );
        return;
      }
      if (!await _downloader.enqueue(newTask)) {
        _finishWithFailure(
          operation,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'The background update task could not be enqueued.',
          ),
        );
        return;
      }
      operation.emit(AppUpdateBinaryEvent.started(artifact.identity));
    } on Object {
      _finishWithFailure(
        operation,
        const AppUpdateFailure(
          code: AppUpdateFailureCode.apkDownloadStartFailed,
          message: 'The background update task could not be started.',
        ),
      );
    }
  }

  Future<DownloadTask?> _taskForArtifact(AppUpdateArtifact artifact) async {
    final taskId = _taskId(artifact.identity);
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) {
      return task;
    }
    final record = await _downloader.database.recordForId(taskId);
    return record?.task is DownloadTask ? record!.task as DownloadTask : null;
  }

  Future<void> _emitRecord(
    _BackgroundDownloadOperation operation,
    TaskRecord record,
  ) async {
    final snapshot = _progressFromRecord(record);
    switch (record.status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
        operation.emit(AppUpdateBinaryEvent.started(operation.identity));
        if (snapshot.progress > 0 || snapshot.receivedBytes > 0) {
          operation.emit(
            AppUpdateBinaryEvent.progress(
              identity: operation.identity,
              receivedBytes: snapshot.receivedBytes,
              totalBytes: snapshot.totalBytes,
              reportedProgress: snapshot.progress,
            ),
          );
        }
      case TaskStatus.paused:
        _finishWithFailure(
          operation,
          const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadFailed,
            message: 'The legacy paused update task must be restarted.',
          ),
        );
      case TaskStatus.complete:
        operation.finish(
          AppUpdateBinaryEvent.completed(
            identity: operation.identity,
            receivedBytes: snapshot.receivedBytes,
            totalBytes: snapshot.totalBytes,
          ),
        );
      case TaskStatus.failed:
      case TaskStatus.notFound:
        _finishWithFailure(
          operation,
          _failureFromRecord(record) ??
              const AppUpdateFailure(
                code: AppUpdateFailureCode.apkDownloadFailed,
                message: 'The background update task failed.',
              ),
        );
      case TaskStatus.canceled:
        operation.finish(
          AppUpdateBinaryEvent.cancelled(
            identity: operation.identity,
            receivedBytes: snapshot.receivedBytes,
            totalBytes: snapshot.totalBytes,
          ),
        );
    }
  }

  void _handleUpdate(TaskUpdate update) {
    if (update.task.group != taskGroup) {
      return;
    }
    final operation = _operations[update.task.taskId];
    if (operation == null) {
      return;
    }
    if (update is TaskProgressUpdate) {
      final progressUpdate = update;
      final snapshot = _progressForUpdate(progressUpdate, operation.identity);
      _progress[update.task.taskId] = snapshot;
      if (progressUpdate.progress >= 0) {
        operation.emit(
          AppUpdateBinaryEvent.progress(
            identity: operation.identity,
            receivedBytes: snapshot.receivedBytes,
            totalBytes: snapshot.totalBytes,
            reportedProgress: snapshot.progress,
          ),
        );
      }
      return;
    }
    if (update is TaskStatusUpdate) {
      final statusUpdate = update;
      final snapshot =
          _progress[update.task.taskId] ??
          const _ProgressSnapshot(receivedBytes: 0, totalBytes: null);
      switch (statusUpdate.status) {
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          operation.emit(AppUpdateBinaryEvent.started(operation.identity));
        case TaskStatus.paused:
          _finishWithFailure(
            operation,
            const AppUpdateFailure(
              code: AppUpdateFailureCode.apkDownloadFailed,
              message: 'The legacy paused update task must be restarted.',
            ),
          );
        case TaskStatus.complete:
          operation.finish(
            AppUpdateBinaryEvent.completed(
              identity: operation.identity,
              receivedBytes: snapshot.receivedBytes,
              totalBytes: snapshot.totalBytes,
            ),
          );
        case TaskStatus.canceled:
          operation.finish(
            AppUpdateBinaryEvent.cancelled(
              identity: operation.identity,
              receivedBytes: snapshot.receivedBytes,
              totalBytes: snapshot.totalBytes,
            ),
          );
        case TaskStatus.failed:
        case TaskStatus.notFound:
          _finishWithFailure(operation, _failureFromStatus(statusUpdate));
      }
    }
  }

  _ProgressSnapshot _progressForUpdate(
    TaskProgressUpdate update,
    AppUpdateArtifactIdentity identity,
  ) {
    final previous = _progress[_taskId(identity)];
    final total = update.expectedFileSize >= 0
        ? update.expectedFileSize
        : previous?.totalBytes;
    final normalized = update.progress.isFinite
        ? update.progress.clamp(0, 1).toDouble()
        : (previous?.progress ?? 0);
    final monotonic = normalized < (previous?.progress ?? 0)
        ? previous!.progress
        : normalized;
    final received = total == null
        ? previous?.receivedBytes ?? 0
        : (total * monotonic).round();
    return _ProgressSnapshot(
      receivedBytes: received,
      totalBytes: total,
      progress: monotonic,
    );
  }

  _ProgressSnapshot _progressFromRecord(TaskRecord record) {
    final previous = _progress[record.taskId];
    final normalized = record.progress.isFinite
        ? record.progress.clamp(0, 1).toDouble()
        : (previous?.progress ?? 0);
    final monotonic = normalized < (previous?.progress ?? 0)
        ? previous!.progress
        : normalized;
    final total = record.expectedFileSize >= 0
        ? record.expectedFileSize
        : previous?.totalBytes;
    return _ProgressSnapshot(
      receivedBytes: total == null
          ? previous?.receivedBytes ?? 0
          : (total * monotonic).round(),
      totalBytes: total,
      progress: monotonic,
    );
  }

  AppUpdateBackgroundTaskStatus _mapStatus(TaskStatus status) {
    return switch (status) {
      TaskStatus.enqueued => AppUpdateBackgroundTaskStatus.enqueued,
      TaskStatus.running => AppUpdateBackgroundTaskStatus.running,
      TaskStatus.paused => AppUpdateBackgroundTaskStatus.paused,
      TaskStatus.waitingToRetry => AppUpdateBackgroundTaskStatus.waitingToRetry,
      TaskStatus.complete => AppUpdateBackgroundTaskStatus.complete,
      TaskStatus.failed => AppUpdateBackgroundTaskStatus.failed,
      TaskStatus.canceled => AppUpdateBackgroundTaskStatus.canceled,
      TaskStatus.notFound => AppUpdateBackgroundTaskStatus.notFound,
    };
  }

  AppUpdateFailure? _failureFromRecord(TaskRecord record) {
    if (record.exception == null) {
      return null;
    }
    return AppUpdateFailure(
      code: AppUpdateFailureCode.apkDownloadFailed,
      message: 'The background update task failed.',
    );
  }

  AppUpdateFailure _failureFromStatus(TaskStatusUpdate update) {
    final code = update.status == TaskStatus.notFound
        ? AppUpdateFailureCode.apkDownloadFailed
        : AppUpdateFailureCode.apkDownloadFailed;
    return AppUpdateFailure(
      code: code,
      message: 'The background update task failed.',
    );
  }

  Map<String, String> _metadataFor(AppUpdateArtifact artifact) {
    return <String, String>{
      'tag': artifact.tag,
      'version': artifact.version.toString(),
      'apkUri': artifact.apkUri.toString(),
      'checksumUri': artifact.checksumUri.toString(),
      'fileName': artifact.fileName,
    };
  }

  AppUpdateArtifact? _artifactFromMetadata(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      final tag = json['tag'];
      final version = json['version'];
      final apkUri = json['apkUri'];
      final checksumUri = json['checksumUri'];
      final fileName = json['fileName'];
      if ([
        tag,
        version,
        apkUri,
        checksumUri,
        fileName,
      ].any((value) => value is! String || value.trim().isEmpty)) {
        return null;
      }
      final candidate = GiteeReleaseCandidate(
        tag: tag as String,
        version: Version.parse(version as String),
        apkUri: Uri.parse(apkUri as String),
        checksumUri: Uri.parse(checksumUri as String),
        releaseNotes: null,
      );
      final artifact = AppUpdateArtifact.fromCandidate(candidate);
      return artifact.fileName == fileName ? artifact : null;
    } on Object {
      return null;
    }
  }

  String _taskId(AppUpdateArtifactIdentity identity) {
    final safe = identity.stableKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'y300-update-$safe';
  }

  bool _samePath(String first, String second) {
    final normalizedFirst = p.normalize(p.absolute(first));
    final normalizedSecond = p.normalize(p.absolute(second));
    return Platform.isWindows
        ? normalizedFirst.toLowerCase() == normalizedSecond.toLowerCase()
        : normalizedFirst == normalizedSecond;
  }

  void _finishWithFailure(
    _BackgroundDownloadOperation operation,
    AppUpdateFailure failure,
  ) {
    operation.finish(
      AppUpdateBinaryEvent.failed(
        identity: operation.identity,
        receivedBytes: 0,
        totalBytes: null,
        failure: failure,
      ),
    );
  }
}

final class _BackgroundDownloadOperation {
  _BackgroundDownloadOperation(this.identity, {required this.onFinished})
    : _controller = StreamController<AppUpdateBinaryEvent>.broadcast();

  final AppUpdateArtifactIdentity identity;
  final void Function() onFinished;
  final StreamController<AppUpdateBinaryEvent> _controller;
  Stream<AppUpdateBinaryEvent>? _stream;
  bool _finished = false;

  Stream<AppUpdateBinaryEvent> get stream => _stream ??= _controller.stream;

  void emit(AppUpdateBinaryEvent event) {
    if (!_finished && !_controller.isClosed) {
      _controller.add(event);
    }
  }

  void finish(AppUpdateBinaryEvent event) {
    if (_finished) {
      return;
    }
    _finished = true;
    onFinished();
    if (!_controller.isClosed) {
      _controller.add(event);
      unawaited(_controller.close());
    }
  }
}

final class _ProgressSnapshot {
  const _ProgressSnapshot({
    required this.receivedBytes,
    required this.totalBytes,
    this.progress = 0,
  });

  final int receivedBytes;
  final int? totalBytes;
  final double progress;
}
