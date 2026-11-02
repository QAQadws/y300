part of 'forum_body_paragraph_row.dart';

/// Qualified numeric paint strip inside one complete legal source group.
/// No source offsets, projection, callback, lease or native object is retained.
final class ForumBodyParagraphPhysicalLineSelector {
  const ForumBodyParagraphPhysicalLineSelector._(
    this._nativeInputIdentity,
    this._group,
    this.selector, {
    required bool empty,
  }) : _empty = empty;
  final Object _nativeInputIdentity;
  final ForumBodyParagraphRowSelector _group;
  final bool _empty;
  final ForumBodyParagraphRowSelector selector;
  int get lineIndex => selector.startLine;

  /// Pure input comparison, not current owner or source authorization.
  bool matchesInput({
    required Object nativeInputIdentity,
    required ForumBodyParagraphRowSelector group,
  }) => _nativeInputIdentity == nativeInputIdentity && _group == group;

  @override
  bool operator ==(Object other) =>
      other is ForumBodyParagraphPhysicalLineSelector &&
      _nativeInputIdentity == other._nativeInputIdentity &&
      _group == other._group &&
      selector == other.selector &&
      _empty == other._empty;
  @override
  int get hashCode =>
      Object.hash(_nativeInputIdentity, _group, selector, _empty);
}

/// Borrows a current legal group and its actual full native line-frame table.
/// Tight font boxes are queried for the COMPLETE group, never a partial
/// grapheme. Boxes must fit a unique measured physical flow frame; source
/// ownership is not inferred from these coordinates. One part consumes a row,
/// query, box, boundary or selector. No shaping, recording or alias is created.
final class ForumBodyParagraphPhysicalLinePreparation {
  ForumBodyParagraphPhysicalLinePreparation({
    required ForumBodyParagraphRowView group,
    required ForumBodyParagraphLineFrames frames,
    required void Function() ensureOwner,
    this.maxLines = 64,
    this.maxBoxes = 4096,
  }) : _group = group,
       _frames = frames,
       _ensureOwner = ensureOwner {
    if (maxLines <= 0 || maxBoxes < 0) {
      throw ArgumentError('Invalid physical-line budget');
    }
    try {
      _guard();
      final parent = group.parent, layout = parent.layout;
      if (!identical(frames.content, parent.content) ||
          frames.nativeInputIdentity != parent.nativeInputIdentity ||
          !identical(frames.lines, layout.lines) ||
          layout.rowIsolationPitch == null) {
        _fail(ForumBodyParagraphRowFailure.source);
      }
      if (group.metrics.lineCount > maxLines) {
        _fail(ForumBodyParagraphRowFailure.limit);
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int maxLines, maxBoxes;
  ForumBodyParagraphRowView? _group;
  ForumBodyParagraphLineFrames? _frames;
  void Function()? _ensureOwner;
  List<Rect>? _bounds = [];
  List<TextBox>? _boxes;
  List<double>? _cuts = [];
  List<ForumBodyParagraphPhysicalLineSelector>? _selectors = [];
  List<ForumBodyParagraphPhysicalLineSelector>? _result;
  int _box = 0, _boundary = 0, _row = 0;
  bool _queried = false, _closed = false, _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Physical-line preparation is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (used < maxParts && !isReady) {
        final group = _group!, layout = group.parent.layout;
        final count = group.metrics.lineCount;
        final start = group.selector.startLine;
        if (_bounds!.length < count) {
          _bounds!.add(
            _frame(layout.lines[start + _bounds!.length], layout.width),
          );
        } else if (!_queried) {
          _boxes = layout.selectionBoxes(
            group.metrics.startUtf16,
            group.metrics.endUtf16,
          );
          if (_boxes!.length > maxBoxes) {
            _fail(ForumBodyParagraphRowFailure.limit);
          }
          _queried = true;
        } else if (_box < _boxes!.length) {
          _consumeBox(_boxes![_box++].toRect());
        } else if (_boundary < count - 1) {
          final own = _envelope(_boundary), next = _envelope(_boundary + 1);
          _requireGap(next.top - own.bottom);
          _cuts!.add((own.bottom + next.top) / 2);
          _boundary++;
        } else if (_row < count) {
          final index = _row++, own = _envelope(index);
          final top = index == 0 ? group.selector.clipTop : _cuts![index - 1];
          final bottom = index == count - 1
              ? group.selector.clipBottom
              : _cuts![index];
          if (top > own.top || bottom < own.bottom || bottom <= top) {
            _fail(ForumBodyParagraphRowFailure.geometry);
          }
          final line = layout.lines[start + index];
          _selectors!.add(
            ForumBodyParagraphPhysicalLineSelector._(
              group.parent.nativeInputIdentity,
              group.selector,
              (
                startLine: start + index,
                endLine: start + index + 1,
                originY: _bounds![index].top.floorToDouble(),
                clipTop: top,
                clipBottom: bottom,
              ),
              empty: line.coverageStartUtf16 == line.coverageEndUtf16,
            ),
          );
        } else {
          _result = UnmodifiableListView(_selectors!);
          _selectors = null;
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

  void _consumeBox(Rect rect) {
    _validateRect(rect);
    final start = _group!.selector.startLine;
    var match = -1;
    for (var i = 0; i < _bounds!.length; i++) {
      final frame = _frames!.frames[start + i];
      if (rect.top >= frame.flowTop && rect.bottom <= frame.flowBottom) {
        if (match >= 0) _fail(ForumBodyParagraphRowFailure.geometry);
        match = i;
      }
    }
    if (match < 0) _fail(ForumBodyParagraphRowFailure.geometry);
    _bounds![match] = _bounds![match].expandToInclude(rect);
  }

  Rect _envelope(int index) {
    final bounds = _bounds![index], clearance = _group!.metrics._paintClearance;
    return Rect.fromLTRB(
      bounds.left,
      bounds.top - clearance.top,
      bounds.right,
      bounds.bottom + clearance.bottom,
    );
  }

  void _requireGap(double gap) {
    if (gap < 1) {
      throw ForumBodyParagraphRowException(
        ForumBodyParagraphRowFailure.isolation,
        requiredPitch:
            (_group!.metrics.rowIsolationPitch + 1 - gap).ceilToDouble() + 1,
      );
    }
  }

  List<ForumBodyParagraphPhysicalLineSelector> takeSelectors() {
    if (_operating) throw StateError('Physical-line preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Physical-line preparation is incomplete');
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
    if (_closed) throw StateError('Physical-line preparation is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Physical-line preparation is retired');
    _group!._guard();
    if (_closed) throw StateError('Physical-line preparation is retired');
  }

  void close() {
    _closed = true;
    _group = null;
    _frames = null;
    _ensureOwner = null;
    _bounds = null;
    _boxes = null;
    _cuts = null;
    _selectors = null;
    _result = null;
  }
}

Never _fail(ForumBodyParagraphRowFailure failure) =>
    throw ForumBodyParagraphRowException(failure);
