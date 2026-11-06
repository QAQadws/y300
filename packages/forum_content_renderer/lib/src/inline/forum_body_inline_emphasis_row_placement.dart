import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../style/forum_body_style_options.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_inline_emphasis_child_bands.dart';

final class ForumBodyInlineEmphasisRow {
  const ForumBodyInlineEmphasisRow._(
    this.lineIndex,
    this.baseTop,
    this.baseBottom,
    this.overEdge,
    this.underEdge,
    this.overBaseline,
    this.underBaseline,
  );
  final int lineIndex;
  final double? baseTop,
      baseBottom,
      overEdge,
      underEdge,
      overBaseline,
      underBaseline;
}

/// One original eligible parent unit, with a source-free natural marker font.
/// The complete original unit remains intact even when it spans physical rows.
final class ForumBodyInlinePlacedEmphasisMark {
  const ForumBodyInlinePlacedEmphasisMark._(
    this.unitIndex,
    this.lineIndex,
    this.fontIndex,
    this.baselineOrigin,
    this.fontOffset,
    this.fontBounds,
  );
  final int unitIndex, lineIndex, fontIndex;
  final Offset baselineOrigin, fontOffset;
  final Rect fontBounds;
}

/// Shared physical-row/side placement, before child replan, final parent layout
/// and complete visible scene/page admission. No native resource is retained.
final class ForumBodyInlineEmphasisRowPlacement {
  ForumBodyInlineEmphasisRowPlacement._(
    this.input,
    List<ForumBodyInlineEmphasisRow> rows,
    List<ForumBodyInlinePlacedEmphasisMark> marks,
  ) : rows = UnmodifiableListView(rows),
      marks = UnmodifiableListView(marks);
  static const revision = 1;
  final ForumBodyInlineEmphasisChildBands input;
  final List<ForumBodyInlineEmphasisRow> rows;
  final List<ForumBodyInlinePlacedEmphasisMark> marks;
}

enum _MixedPlacementPhase {
  rows,
  children,
  parentMarks,
  solve,
  place,
  publish,
  ready,
  retired,
}

/// The one mixed root-row solver. Annotation descendant rows keep their own
/// placement. Each part visits a row, child, actual marker or published value.
final class ForumBodyInlineEmphasisRowPlacementPreparation {
  ForumBodyInlineEmphasisRowPlacementPreparation({
    required ForumBodyInlineEmphasisChildBands input,
    required void Function() ensureOwner,
    this.maxInspectedMarks = 32768,
  }) : _input = input,
       _ensureOwner = ensureOwner {
    if (maxInspectedMarks < 0) throw ArgumentError.value(maxInspectedMarks);
  }
  final int maxInspectedMarks;
  ForumBodyInlineEmphasisChildBands? _input;
  void Function()? _ensureOwner;
  List<_MixedMarkerRow> _work = [];
  List<ForumBodyInlineEmphasisRow> _rows = [];
  List<ForumBodyInlinePlacedEmphasisMark> _marks = [];
  ForumBodyInlineEmphasisRowPlacement? _result;
  int _index = 0, _inspected = 0;
  var _phase = _MixedPlacementPhase.rows;
  bool _operating = false;
  bool get isReady => _phase == _MixedPlacementPhase.ready;
  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var used = 0;
      while (!isReady && used < maxParts) {
        final input = _input!, fonts = input.fonts, geometry = fonts.geometry;
        switch (_phase) {
          case _MixedPlacementPhase.rows:
            if (_work.length < geometry.lineCount) {
              final font = geometry.parentFontBounds[_work.length];
              _work.add(
                _MixedMarkerRow()..includeBase(font?.top, font?.bottom),
              );
            } else {
              _index = 0;
              _phase = _MixedPlacementPhase.children;
            }
          case _MixedPlacementPhase.children:
            if (_index == input.children.length) {
              _index = 0;
              _phase = _MixedPlacementPhase.parentMarks;
            } else {
              final child = input.children[_index++];
              if (child != null) {
                final row = _work[child.lineIndex];
                row.includeBase(child.baseTop, child.baseBottom);
                row.includeEdges(child.overEdge, child.underEdge);
              }
            }
          case _MixedPlacementPhase.parentMarks:
            if (_index < geometry.targets.length) {
              _count();
              final target = geometry.targets[_index],
                  font = fonts.fontForUnit(_index++);
              _work[target.lineIndex].includeMark(
                font.alphabeticBaseline - font.fontBounds.top,
                font.fontBounds.bottom - font.alphabeticBaseline,
                geometry
                    .input
                    .content
                    .runs[target.unit.runIndex]
                    .style
                    .textEmphasis
                    .side,
              );
            } else {
              _index = 0;
              _phase = _MixedPlacementPhase.solve;
            }
          case _MixedPlacementPhase.solve:
            if (_index < _work.length) {
              _rows.add(_work[_index].solve(_index));
              _index++;
            } else {
              _work = [];
              _index = 0;
              _phase = _MixedPlacementPhase.place;
            }
          case _MixedPlacementPhase.place:
            if (_index < geometry.targets.length) {
              final target = geometry.targets[_index],
                  font = fonts.fontForUnit(_index),
                  row = _rows[target.lineIndex];
              final side = geometry
                  .input
                  .content
                  .runs[target.unit.runIndex]
                  .style
                  .textEmphasis
                  .side;
              final baseline = side == ForumBodyEmphasisSide.over
                  ? row.overBaseline!
                  : row.underBaseline!;
              final origin = Offset(0, baseline),
                  offset = Offset(
                    target.governingFontBounds.center.dx -
                        font.fontBounds.center.dx,
                    -font.alphabeticBaseline,
                  );
              final bounds = font.fontBounds.shift(offset).shift(origin);
              if (!bounds.isFinite) _invalid();
              _marks.add(
                ForumBodyInlinePlacedEmphasisMark._(
                  _index,
                  target.lineIndex,
                  fonts.unitFonts[_index],
                  origin,
                  offset,
                  bounds,
                ),
              );
              _index++;
            } else {
              _index = 0;
              _phase = _MixedPlacementPhase.publish;
            }

          case _MixedPlacementPhase.publish:
            _result = ForumBodyInlineEmphasisRowPlacement._(
              input,
              _rows,
              _marks,
            );
            _rows = [];
            _marks = [];
            _phase = _MixedPlacementPhase.ready;
          case _MixedPlacementPhase.ready:
          case _MixedPlacementPhase.retired:
            throw StateError('Mixed emphasis placement is retired');
        }
        used++;
        _guard();
      }
      return used;
    });
  }

  void _count() {
    if (_inspected >= maxInspectedMarks) {
      throw const ForumBodyEmphasisGeometryException(
        ForumBodyEmphasisGeometryFailure.limit,
      );
    }
    _inspected++;
  }

  static Never _invalid() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.geometry,
  );
  ForumBodyInlineEmphasisRowPlacement takePlacement() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Mixed emphasis placement is incomplete');
    final result = _result!;
    close();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Mixed emphasis placement is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _MixedPlacementPhase.retired) {
      throw StateError('Mixed emphasis placement is retired');
    }
    _ensureOwner!();
    if (_phase == _MixedPlacementPhase.retired) {
      throw StateError('Mixed emphasis placement owner is retired');
    }
  }

  void close() {
    _phase = _MixedPlacementPhase.retired;
    _input = null;
    _ensureOwner = null;
    _work = [];
    _rows = [];
    _marks = [];
    _result = null;
  }
}

final class _MixedMarkerRow {
  double? top, bottom, overEdge, underEdge;
  double overDescent = 0, underAscent = 0;
  bool hasOver = false, hasUnder = false;
  static double? min(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : math.min(a, b);
  static double? max(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : math.max(a, b);
  void includeBase(double? first, double? last) {
    if (first != null &&
        (!first.isFinite || last == null || !last.isFinite || last < first)) {
      ForumBodyInlineEmphasisRowPlacementPreparation._invalid();
    }
    top = min(top, first);
    bottom = max(bottom, last);
  }

  void includeEdges(double? over, double? under) {
    overEdge = min(overEdge, over);
    underEdge = max(underEdge, under);
  }

  void includeMark(double ascent, double descent, ForumBodyEmphasisSide side) {
    if (!ascent.isFinite || !descent.isFinite || ascent < 0 || descent < 0) {
      ForumBodyInlineEmphasisRowPlacementPreparation._invalid();
    }
    if (side == ForumBodyEmphasisSide.over) {
      hasOver = true;
      overDescent = math.max(overDescent, descent);
    } else {
      hasUnder = true;
      underAscent = math.max(underAscent, ascent);
    }
  }

  ForumBodyInlineEmphasisRow solve(int index) {
    if ((hasOver || hasUnder) && (top == null || bottom == null)) {
      ForumBodyInlineEmphasisRowPlacementPreparation._invalid();
    }
    final over = hasOver ? min(top, overEdge)! - overDescent : null,
        under = hasUnder ? max(bottom, underEdge)! + underAscent : null;
    if (over != null && !over.isFinite || under != null && !under.isFinite) {
      ForumBodyInlineEmphasisRowPlacementPreparation._invalid();
    }
    return ForumBodyInlineEmphasisRow._(
      index,
      top,
      bottom,
      overEdge,
      underEdge,
      over,
      under,
    );
  }
}
