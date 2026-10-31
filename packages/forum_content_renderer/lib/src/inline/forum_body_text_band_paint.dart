import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Internal ownership for one band's bounded drawing slots, not an independent
/// cache/budget. The owner cache must admit each ticket before committing it.
final class ForumBodyTextBandPaintStore {
  ForumBodyTextBandPaintStore(int slots, this._draw)
    : _pictures = List<ui.Picture?>.filled(slots, null);
  void Function(Canvas)? _draw;
  final List<ui.Picture?> _pictures;
  final _pending = <int, ForumBodyTextBandPaint>{};
  int _preparedCount = 0;
  int _bytes = 0;
  bool _recording = false;
  bool _disposed = false;
  int get preparedCount => _preparedCount;
  int get pendingCount => _pending.length;
  int get approximateBytes => _bytes;
  void _ensureOpen() {
    if (_disposed) throw StateError('Text band paint owner is retired');
  }

  bool isPrepared(int index) {
    RangeError.checkValidIndex(index, _pictures, 'index');
    return !_disposed && _pictures[index] != null;
  }

  ForumBodyTextBandPaint record(int index, Rect clip) {
    _ensureOpen();
    RangeError.checkValidIndex(index, _pictures, 'index');
    if (_recording || _pending.containsKey(index) || _pictures[index] != null) {
      throw StateError('Text band paint is already prepared or recording');
    }
    _recording = true;
    final recorder = ui.PictureRecorder();
    ui.Picture? picture;
    try {
      final canvas = Canvas(recorder, clip)..clipRect(clip);
      _draw!(canvas);
      picture = recorder.endRecording();
      // Picture.onCreate is caller code and may retire the reading owner.
      _ensureOpen();
      final ticket = ForumBodyTextBandPaint._(
        this,
        index,
        picture,
        picture.approximateBytesUsed,
      );
      _pending[index] = ticket;
      _bytes += ticket.approximateBytes;
      return ticket;
    } catch (_) {
      if (recorder.isRecording) recorder.endRecording().dispose();
      picture?.dispose();
      rethrow;
    } finally {
      _recording = false;
    }
  }

  void adopt(ForumBodyTextBandPaint ticket) {
    try {
      _ensureOpen();
      if (!identical(ticket._owner, this) ||
          !ticket.isActive ||
          !identical(_pending[ticket.index], ticket) ||
          _pictures[ticket.index] != null) {
        throw StateError('Text band paint ticket does not belong to this slot');
      }
      _pending.remove(ticket.index);
      _pictures[ticket.index] = ticket._picture;
      _preparedCount++;
      ticket._picture = null;
      ticket._owner = null;
    } catch (_) {
      ticket.close();
      rethrow;
    }
  }

  void _dropPending(ForumBodyTextBandPaint ticket) {
    if (identical(_pending[ticket.index], ticket)) {
      _pending.remove(ticket.index);
      _bytes -= ticket.approximateBytes;
    }
  }

  void paint(int index, Canvas canvas, Offset translation) {
    _ensureOpen();
    final picture = _pictures[index];
    if (picture == null) {
      throw StateError('Text band child paint is not prepared');
    }
    canvas.save();
    try {
      canvas.translate(translation.dx, translation.dy);
      canvas.drawPicture(picture);
    } finally {
      canvas.restore();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _pending.values.toList();
    final pictures = _pictures.whereType<ui.Picture>().toList();
    _pending.clear();
    _pictures.fillRange(0, _pictures.length, null);
    _preparedCount = 0;
    _bytes = 0;
    _draw = null;
    Object? error;
    StackTrace? trace;
    void release(void Function() action) {
      try {
        action();
      } catch (caught, stack) {
        error ??= caught;
        trace ??= stack;
      }
    }

    for (final ticket in pending) {
      release(ticket.close);
    }
    for (final picture in pictures) {
      release(picture.dispose);
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
  }
}

/// A single uncommitted native picture. Closing rejects just this allocation;
/// adopting transfers it to its band. Neither closes the shared glyph owner.
final class ForumBodyTextBandPaint {
  ForumBodyTextBandPaint._(
    this._owner,
    this.index,
    this._picture,
    this.approximateBytes,
  );
  ForumBodyTextBandPaintStore? _owner;
  ui.Picture? _picture;
  final int index;
  final int approximateBytes;
  bool get isActive => _picture != null && _owner?._disposed == false;
  void close() {
    final owner = _owner;
    final picture = _picture;
    _owner = null;
    _picture = null;
    owner?._dropPending(this);
    picture?.dispose();
  }
}
