import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

typedef EncodedImageDimensionLoader =
    Future<ui.Size> Function(String localPath);

/// Reads intrinsic encoded image dimensions without creating a decoded bitmap.
abstract interface class EncodedImageDimensionProbe {
  Future<ui.Size> probe({required String cacheKey, required String localPath});
}

/// Serial, single-flight intrinsic-dimension probe for cached image files.
///
/// Large encoded files still require I/O and format parsing, so unrelated
/// probes are deliberately serialized. Concurrent consumers of the same cache
/// entry and local file share one task.
final class SerialEncodedImageDimensionProbe
    implements EncodedImageDimensionProbe {
  SerialEncodedImageDimensionProbe({
    EncodedImageDimensionLoader loader = loadEncodedImageDimensions,
  }) : _loader = loader;

  final EncodedImageDimensionLoader _loader;
  final _SerialOperationQueue _queue = _SerialOperationQueue();
  final Map<(String, String), Future<ui.Size>> _inFlight =
      <(String, String), Future<ui.Size>>{};

  @override
  Future<ui.Size> probe({required String cacheKey, required String localPath}) {
    final normalizedCacheKey = cacheKey.trim();
    final normalizedPath = localPath.trim();
    if (normalizedCacheKey.isEmpty || normalizedPath.isEmpty) {
      return Future<ui.Size>.error(
        ArgumentError('Image dimension probe identity must not be empty.'),
      );
    }
    final identity = (normalizedCacheKey, normalizedPath);
    final existing = _inFlight[identity];
    if (existing != null) {
      return existing;
    }

    late final Future<ui.Size> task;
    task = _queue.schedule(() => _loader(normalizedPath)).whenComplete(() {
      if (identical(_inFlight[identity], task)) {
        _inFlight.remove(identity);
      }
    });
    _inFlight[identity] = task;
    return task;
  }
}

/// Reads width and height from encoded image metadata without instantiating a
/// codec or allocating the full decoded pixel buffer.
Future<ui.Size> loadEncodedImageDimensions(String localPath) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(localPath);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) {
      throw const FormatException('Invalid encoded image dimensions.');
    }
    return ui.Size(width.toDouble(), height.toDouble());
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

final class _SerialOperationQueue {
  final Queue<_QueuedOperation> _pending = Queue<_QueuedOperation>();
  bool _running = false;

  Future<T> schedule<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending.add(
      _QueuedOperation(() async {
        try {
          completer.complete(await action());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      }),
    );
    _drain();
    return completer.future;
  }

  void _drain() {
    if (_running || _pending.isEmpty) {
      return;
    }
    _running = true;
    final operation = _pending.removeFirst();
    unawaited(
      operation.run().whenComplete(() {
        _running = false;
        _drain();
      }),
    );
  }
}

final class _QueuedOperation {
  const _QueuedOperation(this.run);

  final Future<void> Function() run;
}
