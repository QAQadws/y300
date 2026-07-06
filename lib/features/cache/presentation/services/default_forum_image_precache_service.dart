import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/media/image_display_provider.dart';
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

class DefaultForumImagePrecacheService implements ForumImagePrecacheService {
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
  final Map<String, Future<ForumImagePrecacheResult>> _decodeTasks =
      <String, Future<ForumImagePrecacheResult>>{};

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(ForumImageLoadSpec spec) {
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(success: false),
      );
    }
    final key = request.cacheKey.trim();
    if (key.isEmpty) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(success: false),
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
    final policy = _imageRequestResolver.resolveRenderPolicy(spec);
    if (policy.precacheMode == ForumImagePrecacheMode.none) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(success: false),
      );
    }
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    final key = request?.cacheKey.trim();
    if (request == null || key == null || key.isEmpty) {
      return Future<ForumImagePrecacheResult>.value(
        const ForumImagePrecacheResult(success: false),
      );
    }
    final decodeKey = '$key:${_sizeSignature(expectedDisplaySize)}';
    final existing = _decodeTasks[decodeKey];
    if (existing != null) {
      return existing;
    }
    late final Future<ForumImagePrecacheResult> task;
    task = _decodeGate
        .run(
          () => _precacheDecoded(
            context: context,
            spec: spec,
            expectedDisplaySize: expectedDisplaySize,
            request: request,
          ),
        )
        .whenComplete(() {
          if (identical(_decodeTasks[decodeKey], task)) {
            _decodeTasks.remove(decodeKey);
          }
        });
    _decodeTasks[decodeKey] = task;
    return task;
  }

  Future<ForumImagePrecacheResult> _ensureDiskCached(
    ImageCacheRequest request,
  ) async {
    try {
      final result = await _imageCacheService.ensureCached(request);
      return ForumImagePrecacheResult(
        success: result.success,
        fromDiskCache: result.fromCache,
        cacheKey: request.cacheKey,
        localPath: result.localPath,
      );
    } catch (error) {
      return ForumImagePrecacheResult.failed(error);
    }
  }

  Future<ForumImagePrecacheResult> _precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    required Size? expectedDisplaySize,
    required ImageCacheRequest request,
  }) async {
    try {
      final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final config = createLocalImageConfiguration(context);
      final disk = await ensureDiskCached(spec);
      final localPath = disk.localPath?.trim();
      if (!disk.success || localPath == null || localPath.isEmpty) {
        return disk;
      }
      final provider = _imageProviderBuilder(
        localPath: localPath,
        fit: _fitFor(spec),
        expectedDisplaySize: expectedDisplaySize,
        devicePixelRatio: devicePixelRatio,
      );
      await _precacheInvoker(provider, config);
      return ForumImagePrecacheResult(
        success: true,
        fromDiskCache: disk.fromDiskCache,
        decoded: true,
        cacheKey: request.cacheKey,
        localPath: localPath,
      );
    } catch (error) {
      return ForumImagePrecacheResult.failed(error);
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

ImageProvider defaultForumPrecacheImageProviderBuilder({
  required String localPath,
  required BoxFit fit,
  required Size? expectedDisplaySize,
  required double devicePixelRatio,
}) {
  final fileProvider = FileImage(io.File(localPath));
  final size = expectedDisplaySize;
  if (size == null) {
    return fileProvider;
  }
  return resolveDownscaledImageProvider(
    base: fileProvider,
    fit: fit,
    displaySize: size,
    devicePixelRatio: devicePixelRatio,
    downscalePolicy: const WidthBoundImageDownscalePolicy(),
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
      if (!completer.isCompleted) {
        completer.complete();
      }
      stream.removeListener(listener);
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
