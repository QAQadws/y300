import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_load_trace.dart';

typedef CoverThumbnailEncoder = Future<Uint8List?> Function(ui.Image image);

/// Owns cloned display handles, never resolves or decodes another image.
class LibraryCoverThumbnailWriter {
  LibraryCoverThumbnailWriter({
    required this.cache,
    required this.scheduler,
    this.maxPending = 8,
    this.maxRetainedBytes = 8 * 1024 * 1024,
    CoverThumbnailEncoder? encoder,
    void Function(void Function())? afterFrame,
  }) : _encoder = encoder ?? _encodePng,
       _afterFrame = afterFrame ?? _scheduleAfterFrame {
    cache.addInvalidationListener(discardInactive);
  }

  final LibraryCoverThumbnailStore cache;
  final LibraryCoverDecodeScheduler scheduler;
  final int maxPending;
  final int maxRetainedBytes;
  final CoverThumbnailEncoder _encoder;
  final void Function(void Function()) _afterFrame;
  final Queue<_WriteTask> _pending = Queue<_WriteTask>();
  final Map<String, _WriteTask> _tasks = {};
  int _retainedBytes = 0;
  bool _running = false;
  bool _scheduled = false;
  bool _disposed = false;

  int get pendingCount => _pending.length;
  int get retainedBytes => _retainedBytes;

  /// Clones only accepted requests; the caller always retains its own image.
  void enqueue({
    required LibraryCoverThumbnailKey key,
    required LibraryCoverThumbnailTicket ticket,
    required ui.Image image,
    required bool Function() isActive,
  }) {
    discardInactive();
    final bytes = image.width * image.height * 4;
    if (_disposed ||
        image.colorSpace != ui.ColorSpace.sRGB ||
        !ticket.isValid ||
        !isActive() ||
        (_tasks[key.assetDigest]?.ticket.isValid == true) ||
        _pending.length >= maxPending ||
        bytes + _retainedBytes > maxRetainedBytes) {
      return;
    }
    final task = _WriteTask(key, ticket, image.clone(), bytes, isActive);
    _tasks[key.assetDigest] = task;
    _retainedBytes += bytes;
    _pending.add(task);
    _schedule();
  }

  /// Release stale queued handles even when no further frame is scheduled.
  void discardInactive() {
    final count = _pending.length;
    for (var i = 0; i < count; i++) {
      final task = _pending.removeFirst();
      if (!task.ticket.isValid || !task.isActive()) {
        _release(task);
      } else {
        _pending.addLast(task);
      }
    }
  }

  void _schedule() {
    if (_disposed || _running || _scheduled || _pending.isEmpty) return;
    _scheduled = true;
    _afterFrame(() {
      _scheduled = false;
      if (!_disposed) unawaited(_drainOne());
    });
  }

  Future<void> _drainOne() async {
    if (_running || _disposed || _pending.isEmpty) return;
    _running = true;
    await scheduler.whenIdle();
    if (_disposed || _pending.isEmpty) {
      _running = false;
      return;
    }
    final task = _pending.removeFirst();
    final trace = LibraryCoverLoadTrace(
      task.key.assetDigest.substring(0, 16),
      task.key.width,
      task.key.height,
    );
    try {
      if (!task.ticket.isValid || !task.isActive()) return;
      trace.mark(
        'thumbnailEncodeStart',
        bytes: _retainedBytes,
        pending: _pending.length,
      );
      final bytes = await _encoder(task.image);
      if (!_disposed &&
          task.ticket.isValid &&
          task.isActive() &&
          bytes != null) {
        final committed = await cache.write(
          key: task.key,
          ticket: task.ticket,
          bytes: bytes,
        );
        trace.mark(
          committed ? 'thumbnailWritten' : 'thumbnailSkipped',
          bytes: bytes.length,
        );
      }
    } catch (_) {
      // Encoding/storage is best effort, independent of the displayed frame.
    } finally {
      _release(task);
      _running = false;
      _schedule();
    }
  }

  void _release(_WriteTask task) {
    task.image.dispose();
    _retainedBytes -= task.bytes;
    if (identical(_tasks[task.key.assetDigest], task)) {
      _tasks.remove(task.key.assetDigest);
    }
  }

  void dispose() {
    _disposed = true;
    cache.removeInvalidationListener(discardInactive);
    while (_pending.isNotEmpty) {
      _release(_pending.removeFirst());
    }
  }

  static void _scheduleAfterFrame(void Function() callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  static Future<Uint8List?> _encodePng(ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

class _WriteTask {
  const _WriteTask(
    this.key,
    this.ticket,
    this.image,
    this.bytes,
    this.isActive,
  );
  final LibraryCoverThumbnailKey key;
  final LibraryCoverThumbnailTicket ticket;
  final ui.Image image;
  final int bytes;
  final bool Function() isActive;
}
