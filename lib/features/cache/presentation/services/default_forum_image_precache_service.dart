import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

typedef ForumImageProviderBuilder =
    ImageProvider Function({
      required String localPath,
      required BoxFit fit,
      required Size? expectedDisplaySize,
      required double devicePixelRatio,
    });

typedef ForumImagePrecacheInvoker =
    Future<void> Function(ImageProvider provider, ImageConfiguration config);

class DefaultForumImagePrecacheService
    implements ForumImagePrecacheService, ScopedForumImagePrecacheService {
  DefaultForumImagePrecacheService({
    required ImageCacheService imageCacheService,
    required ForumImageRequestResolver imageRequestResolver,
    int maxConcurrentDiskTasks = 2,
    int maxConcurrentDecodeTasks = 1,
    ForumImageProviderBuilder imageProviderBuilder =
        defaultForumPrecacheImageProviderBuilder,
    ForumImagePrecacheInvoker precacheInvoker =
        defaultForumImagePrecacheInvoker,
  }) : _imageCacheService = imageCacheService,
       _imageRequestResolver = imageRequestResolver,
       _diskGate = _AsyncGate(maxConcurrentDiskTasks),
       _decodeGate = _AsyncGate(maxConcurrentDecodeTasks),
       _imageProviderBuilder = imageProviderBuilder,
       _precacheInvoker = precacheInvoker;

  final ImageCacheService _imageCacheService;
  final ForumImageRequestResolver _imageRequestResolver;
  final _AsyncGate _diskGate;
  final _AsyncGate _decodeGate;
  final ForumImageProviderBuilder _imageProviderBuilder;
  final ForumImagePrecacheInvoker _precacheInvoker;
  final Map<String, Future<ForumImagePrecacheResult>> _diskTasks =
      <String, Future<ForumImagePrecacheResult>>{};
  final Map<String, _SharedForumImageDecodeTask> _decodeTasks =
      <String, _SharedForumImageDecodeTask>{};

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) {
    return _ensureDiskCachedForScope(spec, scope: null);
  }

  @override
  Future<ForumImagePrecacheResult> ensureDiskCachedScoped(
    ForumImageLoadSpec spec, {
    required ForumImageWorkScope scope,
  }) {
    return _ensureDiskCachedForScope(spec, scope: scope);
  }

  Future<ForumImagePrecacheResult> _ensureDiskCachedForScope(
    ForumImageLoadSpec spec, {
    required ForumImageWorkScope? scope,
  }) {
    if (scope != null && !scope.isActive) {
      return Future<ForumImagePrecacheResult>.value(
        ForumImagePrecacheResult.cancelled,
      );
    }
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(
          success: false,
          failureReason: 'no_cache_request',
        ),
      );
    }
    final key = request.cacheKey.trim();
    if (key.isEmpty) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(
          success: false,
          failureReason: 'empty_cache_key',
        ),
      );
    }
    final existing = _diskTasks[key];
    if (existing != null) {
      return existing;
    }
    late final Future<ForumImagePrecacheResult> task;
    task = _diskGate.run(() => _ensureDiskCached(request)).whenComplete(() {
      if (identical(_diskTasks[key], task)) {
        _diskTasks.remove(key);
      }
    });
    _diskTasks[key] = task;
    return task;
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) {
    return _precacheDecodedForScope(
      context: context,
      spec: spec,
      expectedDisplaySize: expectedDisplaySize,
      scope: null,
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecodedScoped({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required ForumImageWorkScope scope,
    Size? expectedDisplaySize,
  }) {
    return _precacheDecodedForScope(
      context: context,
      spec: spec,
      expectedDisplaySize: expectedDisplaySize,
      scope: scope,
    );
  }

  Future<ForumImagePrecacheResult> _precacheDecodedForScope({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required Size? expectedDisplaySize,
    required ForumImageWorkScope? scope,
  }) async {
    if (scope != null && !scope.isActive) {
      return ForumImagePrecacheResult.cancelled;
    }
    final policy = _imageRequestResolver.resolveRenderPolicy(spec);
    if (policy.precacheMode == ForumImagePrecacheMode.none) {
      return const ForumImagePrecacheResult(
        success: false,
        failureReason: 'precache_disabled',
      );
    }
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    final key = request?.cacheKey.trim();
    if (request == null || key == null || key.isEmpty) {
      return const ForumImagePrecacheResult(
        success: false,
        failureReason: 'no_cache_request',
      );
    }
    final disk = scope == null
        ? await ensureDiskCached(spec)
        : await ensureDiskCachedScoped(spec, scope: scope);
    if (scope != null && !scope.isActive) {
      return ForumImagePrecacheResult.cancelled;
    }
    final localPath = disk.localPath?.trim();
    if (!disk.success || localPath == null || localPath.isEmpty) {
      return ForumImagePrecacheResult(
        success: false,
        fromDiskCache: disk.fromDiskCache,
        diskCacheAttempted: disk.diskCacheAttempted,
        decodePrecacheAttempted: false,
        cacheKey: request.cacheKey,
        localPath: localPath,
        error: disk.error,
        failureReason: disk.failureReason ?? 'disk_cache_failed',
      );
    }
    if (!context.mounted) {
      return ForumImagePrecacheResult.cancelled;
    }
    bool requesterIsActive() =>
        context.mounted && (scope == null || scope.isActive);
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final config = createLocalImageConfiguration(context);
    final fit = _fitFor(spec);
    final decodeKey =
        '$key:$localPath:${_sizeSignature(expectedDisplaySize)}:'
        '${devicePixelRatio.toStringAsFixed(2)}:${fit.name}';
    final existing = _decodeTasks[decodeKey];
    if (existing != null) {
      existing.addConsumer(requesterIsActive);
      final result = await existing.future;
      return requesterIsActive() ? result : ForumImagePrecacheResult.cancelled;
    }
    final sharedTask = _SharedForumImageDecodeTask(requesterIsActive);
    late final Future<ForumImagePrecacheResult> task;
    task = _decodeGate
        .run(
          () => _precacheDecoded(
            config: config,
            fit: fit,
            devicePixelRatio: devicePixelRatio,
            expectedDisplaySize: expectedDisplaySize,
            request: request,
            disk: disk,
            localPath: localPath,
            hasActiveConsumer: () => sharedTask.hasActiveConsumer,
          ),
        )
        .whenComplete(() {
          if (identical(_decodeTasks[decodeKey], sharedTask)) {
            _decodeTasks.remove(decodeKey);
          }
        });
    sharedTask.future = task;
    _decodeTasks[decodeKey] = sharedTask;
    final result = await task;
    return requesterIsActive() ? result : ForumImagePrecacheResult.cancelled;
  }

  Future<ForumImagePrecacheResult> _ensureDiskCached(
    ImageCacheRequest request,
  ) async {
    try {
      final result = await _imageCacheService.ensureCached(request);
      return ForumImagePrecacheResult(
        success: result.success,
        fromDiskCache: result.fromCache,
        diskCacheAttempted: true,
        cacheKey: request.cacheKey,
        localPath: result.localPath,
        failureReason: result.success ? null : 'disk_cache_failed',
      );
    } catch (error) {
      return ForumImagePrecacheResult.failed(error, diskCacheAttempted: true);
    }
  }

  Future<ForumImagePrecacheResult> _precacheDecoded({
    required ImageConfiguration config,
    required BoxFit fit,
    required double devicePixelRatio,
    required Size? expectedDisplaySize,
    required ImageCacheRequest request,
    required ForumImagePrecacheResult disk,
    required String localPath,
    required bool Function() hasActiveConsumer,
  }) async {
    try {
      if (!hasActiveConsumer()) {
        return ForumImagePrecacheResult.cancelled;
      }
      final provider = _imageProviderBuilder(
        localPath: localPath,
        fit: fit,
        expectedDisplaySize: expectedDisplaySize,
        devicePixelRatio: devicePixelRatio,
      );
      if (!hasActiveConsumer()) {
        return ForumImagePrecacheResult.cancelled;
      }
      await _precacheInvoker(provider, config);
      return ForumImagePrecacheResult(
        success: true,
        fromDiskCache: disk.fromDiskCache,
        decoded: true,
        diskCacheAttempted: disk.diskCacheAttempted,
        decodePrecacheAttempted: true,
        cacheKey: request.cacheKey,
        localPath: localPath,
      );
    } catch (error) {
      return ForumImagePrecacheResult.failed(
        error,
        decodePrecacheAttempted: true,
      );
    }
  }

  BoxFit _fitFor(ForumImageLoadSpec spec) {
    final policy = _imageRequestResolver.resolveRenderPolicy(spec);
    return switch (policy.downscaleMode) {
      ForumImageDownscaleMode.coverAware => BoxFit.cover,
      _ => BoxFit.contain,
    };
  }

  String _sizeSignature(Size? size) {
    if (size == null || !size.width.isFinite || size.width <= 0) {
      return 'auto';
    }
    final height = size.height.isFinite && size.height > 0
        ? size.height.toStringAsFixed(1)
        : 'auto';
    return '${size.width.toStringAsFixed(1)}x$height';
  }
}

final class _SharedForumImageDecodeTask {
  _SharedForumImageDecodeTask(bool Function() firstConsumerIsActive)
    : _consumers = <bool Function()>[firstConsumerIsActive];

  final List<bool Function()> _consumers;
  late Future<ForumImagePrecacheResult> future;

  bool get hasActiveConsumer => _consumers.any((isActive) => isActive());

  void addConsumer(bool Function() isActive) {
    _consumers.add(isActive);
  }
}

ImageProvider defaultForumPrecacheImageProviderBuilder({
  required String localPath,
  required BoxFit fit,
  required Size? expectedDisplaySize,
  required double devicePixelRatio,
}) {
  final size = expectedDisplaySize;
  if (size == null) {
    return FileImage(io.File(localPath));
  }
  return resolveDownscaledFileImageProvider(
    localPath: localPath,
    fit: fit,
    displaySize: size,
    devicePixelRatio: devicePixelRatio,
  );
}

Future<void> defaultForumImagePrecacheInvoker(
  ImageProvider provider,
  ImageConfiguration config,
) {
  final stream = provider.resolve(config);
  final completer = Completer<void>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo image, bool sync) {
      if (completer.isCompleted) {
        image.dispose();
        return;
      }
      completer.complete();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        image.dispose();
        stream.removeListener(listener);
      });
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

class _AsyncGate {
  _AsyncGate(int maxConcurrent)
    : _maxConcurrent = maxConcurrent <= 0 ? 1 : maxConcurrent;

  final int _maxConcurrent;
  var _running = 0;
  final List<_QueuedTask<Object?>> _queue = <_QueuedTask<Object?>>[];

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue.add(_QueuedTask<T>(task, completer) as _QueuedTask<Object?>);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _running += 1;
      unawaited(_runItem(item));
    }
  }

  Future<void> _runItem(_QueuedTask<Object?> item) async {
    try {
      final result = await item.task();
      item.complete(result);
    } catch (error, stackTrace) {
      item.completeError(error, stackTrace);
    } finally {
      _running -= 1;
      _drain();
    }
  }
}

class _QueuedTask<T> {
  _QueuedTask(this.task, this.completer);

  final Future<T> Function() task;
  final Completer<T> completer;

  void complete(Object? value) {
    completer.complete(value as T);
  }

  void completeError(Object error, StackTrace stackTrace) {
    completer.completeError(error, stackTrace);
  }
}
