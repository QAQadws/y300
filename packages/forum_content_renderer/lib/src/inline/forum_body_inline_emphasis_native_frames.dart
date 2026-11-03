part of 'forum_body_inline_emphasis_row_allocation.dart';

final class _NativeFlowFrames {
  _NativeFlowFrames(this.starts, this.ends, this.nativeAlphabeticBaseline);
  final List<double> starts, ends;
  final double nativeAlphabeticBaseline;
}

/// Full native maximum frames, not logical tight rows or opaque slot envelopes.
/// Explicit paint-origin shift and terminal empty rows remain distinct from
/// complete child overflow; the latter enters allocation via actual child bounds.
final class _NativeFrames {
  _NativeFrames(this._parent, this._ensureOwner, this.maxLines, this.maxBoxes);
  final int maxLines, maxBoxes;
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  List<ForumBodyParagraphMaximumLineFrame>? _boxes;
  List<double> _ends = [], _starts = [];
  int _box = 0, _row = 0;
  double? _top, _bottom, _baseline;
  bool _mapped = false, _closed = false;
  _NativeFlowFrames? _result;
  bool get isReady => _result != null;
  int advance(int maxParts) {
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final layout = _parent!.layout;
        if (_boxes == null) {
          _top = layout.nativeFlowTop;
          _bottom = layout.nativeFlowBottom;
          _baseline = layout.nativeAlphabeticBaseline;
          _boxes = layout.queryMaximumLineFrames();
          if (_boxes!.length > maxBoxes || layout.lineCount > maxLines) {
            _limit();
          }
        } else if (_box < _boxes!.length) {
          final box = _boxes![_box++];
          if (!box.top.isFinite ||
              !box.bottom.isFinite ||
              box.bottom < box.top) {
            _geometryFailure();
          }
          if (_ends.isEmpty || box.bottom != _ends.last) {
            if (_ends.isNotEmpty && box.bottom <= _ends.last) {
              _geometryFailure();
            }
            if (_ends.length >= maxLines) _limit();
            _ends.add(box.bottom);
          }
        } else if (!_mapped) {
          final terminal = forumBodyHasTerminalEmptyLine(
            lines: layout.lines,
            displayText: layout.projection.display.text,
            engineText: layout.projection.engineText,
          );
          if (!_top!.isFinite ||
              !_bottom!.isFinite ||
              !_baseline!.isFinite ||
              _bottom! < _top! ||
              _ends.length != layout.lineCount - (terminal ? 1 : 0) ||
              (_ends.isNotEmpty &&
                  (_ends.first <= _top! ||
                      (terminal
                          ? _ends.last > _bottom!
                          : _ends.last != _bottom!)))) {
            _geometryFailure();
          }
          if (terminal) _ends.add(_bottom!);
          _mapped = true;
        } else if (_row < _ends.length) {
          _starts.add(_row == 0 ? _top! : _ends[_row - 1]);
          _row++;
        } else {
          _result = _NativeFlowFrames(
            UnmodifiableListView(_starts),
            UnmodifiableListView(_ends),
            _baseline!,
          );
          _starts = [];
          _ends = [];
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    }
  }

  _NativeFlowFrames takeFrames() {
    _guard();
    if (!isReady) throw StateError('Mixed native frames are incomplete');
    final result = _result!;
    close();
    return result;
  }

  void _guard() {
    if (_closed) throw StateError('Mixed native frames are retired');
    _ensureOwner!();
    if (_closed || _parent?.isActive != true) {
      throw StateError('Mixed native frame owner is retired');
    }
  }

  void close() {
    _closed = true;
    _parent = null;
    _ensureOwner = null;
    _boxes = null;
    _starts = [];
    _ends = [];
    _result = null;
  }
}

Never _geometryFailure() => throw const ForumBodyEmphasisAllocationException(
  ForumBodyEmphasisAllocationFailure.geometry,
);
