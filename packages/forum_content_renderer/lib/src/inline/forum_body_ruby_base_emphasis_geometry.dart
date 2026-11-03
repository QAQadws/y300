import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_ruby_group_metrics.dart';

/// A measured marker in ruby-column coordinates. The two translations stay
/// separate so a future scene can retain the native font's fractional baseline.
/// This numeric value does not authorize painting or access to the base source.
final class ForumBodyRubyBaseEmphasisMark {
  const ForumBodyRubyBaseEmphasisMark._({
    required this.mark,
    required this.baselineOrigin,
    required this.fontOffset,
    required this.fontBounds,
  });
  final ForumBodyEmphasisLineMark mark;
  final Offset baselineOrigin;
  final Offset fontOffset;
  final Rect fontBounds;
}

/// Numeric placement of an intrinsic base's emphasis outside same-side ruby
/// levels. The ruby stack is built from glyph-only metrics first; decorating
/// that stack must not push its annotation inside the emphasis marks.
///
/// Equal numeric boxes are not source identity. Visible binding still has to
/// qualify the original base, annotations and marker fonts in its current owner.
final class ForumBodyRubyBaseEmphasisGeometry {
  ForumBodyRubyBaseEmphasisGeometry._({
    required this.line,
    required this.group,
    required this.bounds,
    required List<ForumBodyRubyBaseEmphasisMark> marks,
  }) : marks = UnmodifiableListView(marks);
  final ForumBodyEmphasisLineMetrics line;
  final ForumBodyRubyGroupMetrics group;

  /// Keeps the ruby's original origin and baseline. May extend above or below
  /// the group, and is not clipped to its undecorated placeholder dimensions.
  final Rect bounds;
  final List<ForumBodyRubyBaseEmphasisMark> marks;
}

enum _PlacementPhase {
  ranks,
  markMetrics,
  place,
  publish,
  ready,
  transferred,
  closed,
}

/// Pure, bounded placement using already measured fonts and ruby bands. Empty
/// ranks participate through their reserved band, including row-aligned ranks
/// with no local glyph. No shaper, picture, cache or reader owner is retained by
/// the delivered geometry.
final class ForumBodyRubyBaseEmphasisPreparation {
  ForumBodyRubyBaseEmphasisPreparation({
    required ForumBodyEmphasisLineMetrics line,
    required ForumBodyRubyGroupMetrics group,
    required void Function() ensureOwner,
  }) : _line = line,
       _group = group,
       _ensureOwner = ensureOwner,
       _overEdge = group.baseBandTop,
       _underEdge = group.baseBandBottom,
       _bounds = Rect.fromLTWH(0, 0, group.size.width, group.size.height) {
    try {
      _guard();
      if (line.rowInput != null ||
          line.input.content.layoutMode !=
              ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
          line.baseFontBounds != group.baseFontBounds ||
          line.baseAlphabeticBaseline != group.baseFontBaseline) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.metrics,
        );
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyEmphasisLineMetrics? _line;
  ForumBodyRubyGroupMetrics? _group;
  void Function()? _ensureOwner;
  double _overEdge, _underEdge;
  double? _overBaseline, _underBaseline;
  double _overDescent = 0, _underAscent = 0;
  bool _hasOver = false, _hasUnder = false;
  Rect _bounds;
  List<ForumBodyRubyBaseEmphasisMark> _marks = [];
  ForumBodyRubyBaseEmphasisGeometry? _result;
  var _phase = _PlacementPhase.ranks;
  var _index = 0;
  bool _operating = false;
  bool get isReady => _phase == _PlacementPhase.ready;

  ForumBodyEmphasisSide _side(ForumBodyEmphasisLineMark mark) {
    final input = _line!.input;
    return input
        .content
        .runs[input.units[mark.unitIndex].runIndex]
        .style
        .textEmphasis
        .side;
  }

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Ruby emphasis placement is reentrant');
    _operating = true;
    var parts = 0;
    try {
      _guard();
      while (!isReady && parts < maxParts) {
        final line = _line!, group = _group!;
        switch (_phase) {
          case _PlacementPhase.ranks:
            if (_index < group.annotations.length) {
              final annotation = group.annotations[_index++];
              // Do not filter hasAnnotation: an empty local RT may still have
              // a real shared row band established by another column or span.
              if (annotation.side == ForumBodyRubySide.over) {
                _hasOver = true;
                _overEdge = math.min(_overEdge, annotation.bandTop);
              } else {
                _hasUnder = true;
                _underEdge = math.max(_underEdge, annotation.bandBottom);
              }
            } else {
              _index = 0;
              _phase = _PlacementPhase.markMetrics;
            }
          case _PlacementPhase.markMetrics:
            if (_index < line.marks.length) {
              final mark = line.marks[_index++];
              final baseline =
                  group.baseOffset.dy + mark.baseRelativeAlphabeticBaseline;
              if (_side(mark) == ForumBodyEmphasisSide.over) {
                _overBaseline = math.min(_overBaseline ?? baseline, baseline);
                _overDescent = math.max(
                  _overDescent,
                  mark.scaledFontBounds.bottom - mark.scaledAlphabeticBaseline,
                );
              } else {
                _underBaseline = math.max(_underBaseline ?? baseline, baseline);
                _underAscent = math.max(
                  _underAscent,
                  mark.scaledAlphabeticBaseline - mark.scaledFontBounds.top,
                );
              }
            } else {
              if (_hasOver && _overBaseline != null) {
                _overBaseline = math.min(
                  _overBaseline!,
                  _overEdge - _overDescent,
                );
              }
              if (_hasUnder && _underBaseline != null) {
                _underBaseline = math.max(
                  _underBaseline!,
                  _underEdge + _underAscent,
                );
              }
              _index = 0;
              _phase = _PlacementPhase.place;
            }
          case _PlacementPhase.place:
            if (_index < line.marks.length) {
              final mark = line.marks[_index++];
              final origin = Offset(
                group.baseOffset.dx,
                _side(mark) == ForumBodyEmphasisSide.over
                    ? _overBaseline!
                    : _underBaseline!,
              );
              final offset = Offset(
                mark.baseRelativeOffset.dx,
                -mark.scaledAlphabeticBaseline,
              );
              final bounds = mark.scaledFontBounds.shift(offset).shift(origin);
              _marks.add(
                ForumBodyRubyBaseEmphasisMark._(
                  mark: mark,
                  baselineOrigin: origin,
                  fontOffset: offset,
                  fontBounds: bounds,
                ),
              );
              _bounds = _bounds.expandToInclude(bounds);
            } else {
              _phase = _PlacementPhase.publish;
            }
          case _PlacementPhase.publish:
            _result = ForumBodyRubyBaseEmphasisGeometry._(
              line: line,
              group: group,
              bounds: _bounds,
              marks: _marks,
            );
            _marks = [];
            _phase = _PlacementPhase.ready;
          case _PlacementPhase.ready:
          case _PlacementPhase.transferred:
          case _PlacementPhase.closed:
            throw StateError('Ruby emphasis placement is retired');
        }
        parts++;
        _guard();
      }
      return parts;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyRubyBaseEmphasisGeometry takeGeometry() {
    if (_operating) throw StateError('Ruby emphasis placement is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Ruby emphasis placement is incomplete');
      final result = _result!;
      _phase = _PlacementPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _PlacementPhase.closed ||
        _phase == _PlacementPhase.transferred) {
      throw StateError('Ruby emphasis placement is retired');
    }
    _ensureOwner!();
    if (_phase == _PlacementPhase.closed) {
      throw StateError('Ruby emphasis placement owner is retired');
    }
  }

  void _drop() {
    _line = null;
    _group = null;
    _ensureOwner = null;
    _marks.clear();
    _result = null;
  }

  void close() {
    if (_phase == _PlacementPhase.closed ||
        _phase == _PlacementPhase.transferred) {
      return;
    }
    _phase = _PlacementPhase.closed;
    _drop();
  }
}
