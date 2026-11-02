import 'dart:collection';

import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';

enum ForumBodyParagraphLineFrameFailure { source, geometry, limit }

final class ForumBodyParagraphLineFrameException implements Exception {
  const ForumBodyParagraphLineFrameException(this.failure);
  final ForumBodyParagraphLineFrameFailure failure;
  @override
  String toString() => 'ForumBodyParagraphLineFrameException(${failure.name})';
}

/// Physical geometry only. A terminal empty row has no native maximum box;
/// its flow extent still ends at the actual native paragraph height.
final class ForumBodyParagraphLineFrame {
  const ForumBodyParagraphLineFrame._(
    this.maximum,
    this.flowTop,
    this.flowBottom,
  );
  final ForumBodyParagraphMaximumLineFrame? maximum;

  /// Contiguous native flow endpoints, using the preceding measured box end.
  /// A maximum box's top may include leading and does not replace flowTop.
  final double flowTop, flowBottom;
}

/// Numeric snapshot without a cache, lease, callback or native paragraph.
/// Actual line/source ranges remain separate from measured maximum boxes.
final class ForumBodyParagraphLineFrames {
  ForumBodyParagraphLineFrames._(
    ForumBodyParagraphLease parent,
    List<ForumBodyParagraphLineFrame> frames,
  ) : content = parent.content,
      nativeInputIdentity = parent.nativeInputIdentity,
      lines = parent.layout.lines,
      frames = UnmodifiableListView(frames),
      width = parent.layout.width,
      height = parent.layout.height,
      alphabeticBaseline = parent.layout.alphabeticBaseline,
      nativeAlphabeticBaseline = parent.layout.nativeAlphabeticBaseline;
  static const revision = 1;
  final ForumBodyParagraphContent content;
  final Object nativeInputIdentity;
  final List<ForumBodyParagraphLine> lines;
  final List<ForumBodyParagraphLineFrame> frames;
  final double width, height;

  /// Parent's existing logical layout baseline, not a glyph paint coordinate.
  final double alphabeticBaseline;
  final double nativeAlphabeticBaseline;
}

/// Borrows an existing wrapping paragraph. One part queries native full-text
/// boxes, consumes one box, validates the mapping, or publishes one row/result.
/// Native frame order must uniquely match the actual logical row sequence;
/// coincident/degenerate frames fail explicitly, never guess source ownership.
final class ForumBodyParagraphLineFramePreparation {
  ForumBodyParagraphLineFramePreparation({
    required ForumBodyParagraphLease parent,
    required void Function() ensureOwner,
    this.maxLines = 4096,
    this.maxBoxes = 32768,
  }) : _parent = parent,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxBoxes < 0) {
      throw ArgumentError('Invalid line-frame budget');
    }
    try {
      _guard();
      if (parent.content.isSourceFree ||
          parent.content.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
        _fail(ForumBodyParagraphLineFrameFailure.source);
      }
      if (parent.layout.lineCount > maxLines) {
        _fail(ForumBodyParagraphLineFrameFailure.limit);
      }
      _terminal = parent.layout.hasTerminalEmptyLine;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxBoxes;
  ForumBodyParagraphLease? _parent;
  void Function()? _ensureOwner;
  List<ForumBodyParagraphMaximumLineFrame>? _boxes;
  List<ForumBodyParagraphMaximumLineFrame>? _groups = [];
  List<ForumBodyParagraphLineFrame>? _frames = [];
  ForumBodyParagraphLineFrames? _result;
  int _box = 0, _row = 0;
  bool _terminal = false, _mapped = false, _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Line-frame preparation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final layout = _parent!.layout;
        if (_boxes == null) {
          _boxes = layout.queryMaximumLineFrames();
          if (_boxes!.length > maxBoxes) {
            _fail(ForumBodyParagraphLineFrameFailure.limit);
          }
        } else if (_box < _boxes!.length) {
          final frame = _boxes![_box++];
          if (!frame.top.isFinite ||
              !frame.bottom.isFinite ||
              frame.bottom < frame.top) {
            _fail(ForumBodyParagraphLineFrameFailure.geometry);
          }
          final groups = _groups!;
          if (groups.isEmpty || groups.last != frame) {
            if (groups.isNotEmpty && frame.bottom <= groups.last.bottom) {
              _fail(ForumBodyParagraphLineFrameFailure.geometry);
            }
            if (groups.length >= maxLines) {
              _fail(ForumBodyParagraphLineFrameFailure.limit);
            }
            groups.add(frame);
          }
        } else if (!_mapped) {
          final groups = _groups!;
          if (groups.length != layout.lineCount - (_terminal ? 1 : 0) ||
              !layout.height.isFinite ||
              layout.height < 0 ||
              (groups.isNotEmpty &&
                  (groups.first.bottom <= 0 ||
                      (_terminal
                          ? groups.last.bottom > layout.height
                          : groups.last.bottom != layout.height)))) {
            _fail(ForumBodyParagraphLineFrameFailure.geometry);
          }
          _mapped = true;
        } else if (_row < layout.lineCount) {
          final index = _row++;
          _frames!.add(
            ForumBodyParagraphLineFrame._(
              index < _groups!.length ? _groups![index] : null,
              index == 0 ? 0 : _groups![index - 1].bottom,
              index < _groups!.length ? _groups![index].bottom : layout.height,
            ),
          );
        } else {
          _result = ForumBodyParagraphLineFrames._(_parent!, _frames!);
          _frames = null;
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyParagraphLineFrames takeFrames() {
    if (_operating) throw StateError('Line-frame preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Line-frame preparation is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Line-frame preparation is retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true || _parent!.layout.isDisposed) {
      throw StateError('Line-frame owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _ensureOwner = null;
    _boxes = null;
    _groups = null;
    _frames = null;
    _result = null;
  }
}

Never _fail(ForumBodyParagraphLineFrameFailure failure) =>
    throw ForumBodyParagraphLineFrameException(failure);
