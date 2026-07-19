import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/models/app_update_binary_event.dart';
import 'package:y300/features/app_update/domain/models/app_update_failure.dart';
import 'package:y300/features/app_update/domain/services/app_update_binary_downloader.dart';

final class DioAppUpdateBinaryDownloader implements AppUpdateBinaryDownloader {
  DioAppUpdateBinaryDownloader({
    required Dio dio,
    this.requestTimeout = const Duration(minutes: 5),
    this.maxApkBytes = defaultMaxApkBytes,
  }) : _dio = dio;

  static const int defaultMaxApkBytes = 512 * 1024 * 1024;

  final Dio _dio;
  final Duration requestTimeout;
  final int maxApkBytes;
  _DownloadOperation? _active;

  @override
  Stream<AppUpdateBinaryEvent> download(
    AppUpdateArtifact artifact, {
    required String stagingPath,
  }) {
    final identity = artifact.identity;
    final active = _active;
    if (active != null) {
      if (active.identity.stableKey == identity.stableKey) {
        return active.stream;
      }
      return Stream<AppUpdateBinaryEvent>.value(
        AppUpdateBinaryEvent.failed(
          identity: identity,
          receivedBytes: 0,
          totalBytes: null,
          failure: const AppUpdateFailure(
            code: AppUpdateFailureCode.apkDownloadStartFailed,
            message: 'Another update download is already in progress.',
          ),
        ),
      );
    }

    final operation = _DownloadOperation(
      identity: identity,
      stagingPath: stagingPath,
    );
    _active = operation;
    // Let the caller attach its listener before the first event is emitted.
    scheduleMicrotask(() => _run(operation, artifact));
    return operation.stream;
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    if (active == null) {
      return;
    }
    active.cancelToken.cancel('The update download was cancelled.');
    await active.done;
  }

  Future<void> dispose() async {
    await cancel();
  }

  Future<void> _run(
    _DownloadOperation operation,
    AppUpdateArtifact artifact,
  ) async {
    File? file;
    IOSink? sink;
    var receivedBytes = 0;
    int? totalBytes;
    var requestStarted = false;

    operation.emit(AppUpdateBinaryEvent.started(operation.identity));
    try {
      file = File(operation.stagingPath);
      await file.parent.create(recursive: true);
      sink = file.openWrite(mode: FileMode.writeOnly);
      requestStarted = true;

      final response = await _dio.get<ResponseBody>(
        artifact.apkUri.toString(),
        cancelToken: operation.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          connectTimeout: requestTimeout,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
          headers: const <String, String>{
            Headers.acceptHeader:
                'application/vnd.android.package-archive, application/octet-stream',
          },
          validateStatus: (status) => status == 200,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const _MissingResponseBodyException();
      }
      totalBytes = body.contentLength > 0 ? body.contentLength : null;
      if (totalBytes != null && totalBytes > maxApkBytes) {
        throw const _ApkSizeExceededException();
      }

      await for (final chunk in body.stream) {
        if (chunk.isEmpty) {
          continue;
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxApkBytes) {
          throw const _ApkSizeExceededException();
        }
        sink.add(chunk);
        // Progress is emitted after flush, so it represents bytes persisted
        // to the staging file rather than bytes merely received by Dio.
        await sink.flush();
        operation.emit(
          AppUpdateBinaryEvent.progress(
            identity: operation.identity,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _finish(
        operation,
        AppUpdateBinaryEvent.completed(
          identity: operation.identity,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        ),
      );
    } on Object catch (error) {
      await _closeSink(sink);
      sink = null;
      await _deletePartial(file);
      final failure = _mapFailure(
        error,
        operation.cancelToken,
        requestStarted: requestStarted,
      );
      final event = failure.code == AppUpdateFailureCode.apkDownloadCancelled
          ? AppUpdateBinaryEvent.cancelled(
              identity: operation.identity,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
            )
          : AppUpdateBinaryEvent.failed(
              identity: operation.identity,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
              failure: failure,
            );
      _finish(operation, event);
    } finally {
      await _closeSink(sink);
      if (identical(_active, operation)) {
        _active = null;
      }
    }
  }

  void _finish(_DownloadOperation operation, AppUpdateBinaryEvent event) {
    if (identical(_active, operation)) {
      _active = null;
    }
    operation.finish(event);
  }

  AppUpdateFailure _mapFailure(
    Object error,
    CancelToken cancelToken, {
    required bool requestStarted,
  }) {
    if (cancelToken.isCancelled ||
        error is DioException && error.type == DioExceptionType.cancel) {
      return const AppUpdateFailure(
        code: AppUpdateFailureCode.apkDownloadCancelled,
        message: 'The update download was cancelled.',
      );
    }
    if (error is _ApkSizeExceededException) {
      return const AppUpdateFailure(
        code: AppUpdateFailureCode.apkSizeExceeded,
        message: 'The downloaded APK is larger than the allowed limit.',
      );
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return const AppUpdateFailure(
          code: AppUpdateFailureCode.requestTimeout,
          message: 'The update download timed out.',
        );
      }
      if (error.type == DioExceptionType.connectionError) {
        return const AppUpdateFailure(
          code: AppUpdateFailureCode.networkUnavailable,
          message: 'The update download could not reach Gitee.',
        );
      }
    }
    return AppUpdateFailure(
      code: requestStarted
          ? AppUpdateFailureCode.apkDownloadFailed
          : AppUpdateFailureCode.apkDownloadStartFailed,
      message: requestStarted
          ? 'The update APK download failed.'
          : 'The update APK download could not be started.',
    );
  }

  Future<void> _deletePartial(File? file) async {
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A cleanup failure must not hide the original download failure.
    }
  }

  Future<void> _closeSink(IOSink? sink) async {
    if (sink == null) {
      return;
    }
    try {
      await sink.close();
    } on Object {
      // The original network or filesystem error is more actionable.
    }
  }
}

final class _DownloadOperation {
  _DownloadOperation({required this.identity, required this.stagingPath})
    : _controller = StreamController<AppUpdateBinaryEvent>.broadcast();

  final AppUpdateArtifactIdentity identity;
  final String stagingPath;
  final CancelToken cancelToken = CancelToken();
  final StreamController<AppUpdateBinaryEvent> _controller;
  Stream<AppUpdateBinaryEvent>? _stream;
  final Completer<void> _done = Completer<void>();

  Stream<AppUpdateBinaryEvent> get stream => _stream ??= _controller.stream;

  Future<void> get done => _done.future;

  void emit(AppUpdateBinaryEvent event) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(event);
  }

  void finish(AppUpdateBinaryEvent event) {
    if (_controller.isClosed) {
      return;
    }
    emit(event);
    unawaited(_controller.close());
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

final class _MissingResponseBodyException implements Exception {
  const _MissingResponseBodyException();
}

final class _ApkSizeExceededException implements Exception {
  const _ApkSizeExceededException();
}
