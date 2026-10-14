import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/core/media/encoded_image_dimension_probe.dart';
import 'package:y300/core/media/image_downscale_policy.dart';
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
    implements
        ForumImagePrecacheService,
        BoundedForumImagePrecacheService,
        RetryableForumImagePrecacheService {
  DefaultForumImagePrecacheService({
    required ImageCacheService imageCacheService,
    required ForumImageRequestResolver imageRequestResolver,
    int maxConcurrentDiskTasks = 2,
    int maxConcurrentDecodeTasks = 1,
    EncodedImageDimensionProbe? dimensionProbe,
    ForumImageProviderBuilder imageProviderBuilder =
        defaultForumPrecacheImageProviderBuilder,
    ForumImagePrecacheInvoker precacheInvoker =
        defaultForumImagePrecacheInvoker,
  }) : _imageCacheService = imageCacheService,
       _imageRequestResolver = imageRequestResolver,
       _dimensionProbe = dimensionProbe ?? SerialEncodedImageDimensionProbe(),
       _diskGate = _AsyncGate(maxConcurrentDiskTasks),
       _decodeGate = _AsyncGate(maxConcurrentDecodeTasks),
       _imageProviderBuilder = imageProviderBuilder,
       _precacheInvoker = precacheInvoker;

  final ImageCacheService _imageCacheService;
  final ForumImageRequestResolver _imageRequestResolver;
  final EncodedImageDimensionProbe _dimensionProbe;
  final _AsyncGate _diskGate;
  final _AsyncGate _decodeGate;
  final ForumImageProviderBuilder _imageProviderBuilder;
  final ForumImagePrecacheInvoker _precacheInvoker;
  final Map<String, _SharedForumImageDecodeTask> _diskTasks = {};
  final Map<Object, _SharedForumImageDecodeTask> _decodeTasks = {};

  @override
  void allowRetry(ForumImageLoadSpec spec) {
    final service = _imageCacheService;
    if (service is! ImageCacheFailureControl) return;
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    if (request != null) {
      (service as ImageCacheFailureControl).allowRetry(request);
    }
  }

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
      existing.addConsumer(() => scope == null || scope.isActive);
      return _resultForScope(existing.future, scope);
    }
    final shared = _SharedForumImageDecodeTask(
      () => scope == null || scope.isActive,
    );
    late final Future<ForumImagePrecacheResult> task;
    task = _diskGate
        .run(
          () => shared.hasActiveConsumer
              ? _ensureDiskCached(request)
              : Future.value(ForumImagePrecacheResult.cancelled),
        )
        .whenComplete(() {
          if (identical(_diskTasks[key], shared)) {
            _diskTasks.remove(key);
          }
        });
    shared.future = task;
    _diskTasks[key] = shared;
    return _resultForScope(task, scope);
  }

  Future<ForumImagePrecacheResult> _resultForScope(
    Future<ForumImagePrecacheResult> task,
    ForumImageWorkScope? scope,
  ) async {
    final result = await task;
    return scope == null || scope.isActive
        ? result
        : ForumImagePrecacheResult.cancelled;
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
    int? maxDecodedBytes,
  }) {
    return _precacheDecodedForScope(
      context: context,
      spec: spec,
      expectedDisplaySize: expectedDisplaySize,
      scope: null,
      maxDecodedBytes: maxDecodedBytes,
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecodedScoped({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required ForumImageWorkScope scope,
    Size? expectedDisplaySize,
    int? maxDecodedBytes,
  }) {
    return _precacheDecodedForScope(
      context: context,
      spec: spec,
      expectedDisplaySize: expectedDisplaySize,
      scope: scope,
      maxDecodedBytes: maxDecodedBytes,
    );
  }

  Future<ForumImagePrecacheResult> _precacheDecodedForScope({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required Size? expectedDisplaySize,
    required ForumImageWorkScope? scope,
    required int? maxDecodedBytes,
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
    if (maxDecodedBytes != null) {
      final size = expectedDisplaySize;
      bool admitted =
          size != null &&
          size.width.isFinite &&
          size.width > 0 &&
          maxDecodedBytes > 0 &&
          fit != BoxFit.cover;
      if (admitted) {
        try {
          final intrinsic = await _dimensionProbe.probe(
            cacheKey: key,
            localPath: localPath,
          );
          if (!requesterIsActive()) return ForumImagePrecacheResult.cancelled;
          final bytes = estimateWidthBoundDecodedBytes(
            intrinsicSize: intrinsic,
            displaySize: size,
            devicePixelRatio: devicePixelRatio,
          );
          admitted = bytes != null && bytes <= maxDecodedBytes;
        } catch (_) {
          admitted = false;
        }
      }
      if (!requesterIsActive()) return ForumImagePrecacheResult.cancelled;
      if (!admitted) {
        return ForumImagePrecacheResult(
          success: true,
          fromDiskCache: disk.fromDiskCache,
          diskCacheAttempted: disk.diskCacheAttempted,
          cacheKey: key,
          localPath: localPath,
          failureReason: 'decode_admission_skipped',
        );
      }
    }
    final ImageProvider provider;
    final Object decodeKey;
    try {
      provider = _imageProviderBuilder(
        localPath: localPath,
        fit: fit,
        expectedDisplaySize: expectedDisplaySize,
        devicePixelRatio: devicePixelRatio,
      );
      decodeKey = await provider.obtainKey(config);
    } catch (error) {
      return ForumImagePrecacheResult.failed(
        error,
        failureReason: 'decode_provider_failed',
      );
    }
    if (!requesterIsActive()) return ForumImagePrecacheResult.cancelled;
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
            provider: provider,
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
    required ImageProvider provider,
    required ImageCacheRequest request,
    required ForumImagePrecacheResult disk,
    required String localPath,
    required bool Function() hasActiveConsumer,
  }) async {
    try {
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
