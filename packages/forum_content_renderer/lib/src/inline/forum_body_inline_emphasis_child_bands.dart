import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_ruby_atom_plan.dart';
import 'forum_body_ruby_band_stack.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';

/// Font and annotation clearance in the actual mixed parent's coordinates.
/// Root leading stays in its enclosing frame, not in the glyph base band.
final class ForumBodyInlineEmphasisChildBand {
  const ForumBodyInlineEmphasisChildBand._({
    required this.atomIndex,
    required this.lineIndex,
    required this.source,
    required this.glyphOrigin,
    required this.baseTop,
    required this.baseBottom,
    required this.overEdge,
    required this.underEdge,
    required this.overBaseline,
    required this.underBaseline,
    required this.overAnnotationMarkerBounds,
    required this.underAnnotationMarkerBounds,
  });
  final int atomIndex, lineIndex;
  final ForumBodyRubyAtomPlan source;

  /// Root glyph coordinates translated to the actual parent's paint plane.
  /// This never translates DOM/display/semantic source coordinates.
  final Offset glyphOrigin;
  final double baseTop, baseBottom;

  /// Font-only annotation reservations, including existing virtual empty RTs.
  final double? overEdge, underEdge;

  /// Current base-row mark baselines, kept separate from annotation marks.
  final double? overBaseline, underBaseline;
  final Rect? overAnnotationMarkerBounds, underAnnotationMarkerBounds;
}

/// Source-bound numeric inputs only. Child fonts/scene readiness and the final
/// complete parent allocation still need qualification by their visible owner.
final class ForumBodyInlineEmphasisChildBands {
  ForumBodyInlineEmphasisChildBands._(
    this.fonts,
    this.page,
    List<ForumBodyInlineEmphasisChildBand?> children,
  ) : children = UnmodifiableListView(children);
  static const revision = 1;
  final ForumBodyInlineEmphasisFontMetrics fonts;
  final ForumBodyInlinePageContent page;

  /// Null only for an actually trimmed soft slot, which contributes no paint.
  final List<ForumBodyInlineEmphasisChildBand?> children;
}

enum _ChildBandPhase { atoms, ranks, contexts, finish, publish, ready, retired }

/// Reuses final aligned child geometry. Each part visits one atom, annotation
/// rank or existing decoration context; no shaping, cache lookup or recording.
final class ForumBodyInlineEmphasisChildBandsPreparation {
  ForumBodyInlineEmphasisChildBandsPreparation({
    required ForumBodyInlineEmphasisFontMetrics fonts,
    required ForumBodyInlinePageContent page,
    required ForumBodyInlineParagraphLease parent,
    required void Function() ensureOwner,
  }) : _fonts = fonts,
       _page = page,
       _parent = parent,
       _ensureOwner = ensureOwner {
    try {
      _guard();
      final geometry = fonts.geometry;
      if (!identical(page.content, geometry.input.content) ||
          !identical(parent.content, geometry.input.glyphInput.glyphs) ||
          !identical(geometry.lines, parent.layout.lines) ||
          geometry.nativeInputIdentity != parent.nativeInputIdentity ||
          fonts.parentRequest.layoutMode != page.layoutMode ||
          page.rubyAtoms.length != geometry.atomLineIndices.length) {
        _fail(ForumBodyEmphasisGeometryFailure.source);
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyInlineEmphasisFontMetrics? _fonts;
  ForumBodyInlinePageContent? _page;
  ForumBodyInlineParagraphLease? _parent;
  void Function()? _ensureOwner;
  List<ForumBodyInlineEmphasisChildBand?> _children = [];
  ForumBodyInlineEmphasisChildBands? _result;
  var _phase = _ChildBandPhase.atoms;
  bool _operating = false;
  int _index = 0, _rank = 0, _context = 0;
  double _top = 0, _bottom = 0, _over = 0, _under = 0;
  double? _overEdge, _underEdge, _overBaseline, _underBaseline;
  Rect? _overAnnotationMarks, _underAnnotationMarks;
  Offset _origin = Offset.zero;
  ForumBodyRubyGroupMetrics? _group;
  ForumBodyRubyLevelMetrics? _level;
  ForumBodyRubyTreeDecorationBands? _decoration;
  ForumBodyRubyPhysicalRow? _rootRow;
  bool get isReady => _phase == _ChildBandPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var parts = 0;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _ChildBandPhase.atoms:
            if (_index == _page!.rubyAtoms.length) {
              _phase = _ChildBandPhase.publish;
            } else {
              _begin();
            }
          case _ChildBandPhase.ranks:
            final count =
                _group?.annotations.length ?? _level!.annotations.length;
            if (_rank < count) {
              _annotation(_rank++);
            } else {
              _phase = _ChildBandPhase.contexts;
            }
          case _ChildBandPhase.contexts:
            final decoration = _decoration;
            if (decoration != null && _context < decoration.contexts.length) {
              final context = decoration.contexts[_context++];
              if (context.physicalRow == _rootRow) {
                _includeEdges(
                  context.baseAncestorOverEdge == null
                      ? null
                      : _origin.dy + context.baseAncestorOverEdge!,
                  context.baseAncestorUnderEdge == null
                      ? null
                      : _origin.dy + context.baseAncestorUnderEdge!,
                );
              }
            } else {
              _phase = _ChildBandPhase.finish;
            }
          case _ChildBandPhase.finish:
            _check(_top);
            _check(_bottom);
            if (_top > _bottom) _fail(ForumBodyEmphasisGeometryFailure.boxes);
            for (final value in [
              _overEdge,
              _underEdge,
              _overBaseline,
              _underBaseline,
            ]) {
              if (value != null) _check(value);
            }
            _children.add(
              ForumBodyInlineEmphasisChildBand._(
                atomIndex: _index,
                lineIndex: _fonts!.geometry.atomLineIndices[_index],
                source: _page!.rubyAtoms[_index],
                glyphOrigin: _origin,
                baseTop: _top,
                baseBottom: _bottom,
                overEdge: _overEdge,
                underEdge: _underEdge,
                overBaseline: _overBaseline,
                underBaseline: _underBaseline,
                overAnnotationMarkerBounds: _overAnnotationMarks,
                underAnnotationMarkerBounds: _underAnnotationMarks,
              ),
            );
            _index++;
            _clearCurrent();
            _phase = _ChildBandPhase.atoms;
          case _ChildBandPhase.publish:
            _result = ForumBodyInlineEmphasisChildBands._(
              _fonts!,
              _page!,
              _children,
            );
            _children = [];
            _phase = _ChildBandPhase.ready;
          case _ChildBandPhase.ready:
          case _ChildBandPhase.retired:
            throw StateError('Inline child bands are retired');
        }
        parts++;
        _guard();
      }
      return parts;
    });
  }

  void _begin() {
    final page = _page!, layout = _parent!.layout;
    final dimension = page.dimensions[_index],
        actual = layout.dimensions[_index];
    if (dimension.size != actual.size ||
        dimension.alignment != actual.alignment ||
        dimension.baseline != actual.baseline ||
        dimension.baselineOffset != actual.baselineOffset ||
        page.trimmedAtomIndices.contains(_index) !=
            layout.isAtomTrimmed(_index)) {
      _fail(ForumBodyEmphasisGeometryFailure.source);
    }
    if (layout.isAtomTrimmed(_index)) {
      _children.add(null);
      _index++;
      return;
    }
    final slot = layout.atomBoxes[_index].toRect();
    final source = page.rubyAtoms[_index];
    ForumBodyRubyAtomFrame? frame;
    ForumBodyRubyTreeEmphasisPlan? emphasis;
    ForumBodyRubyTreeContainerMetrics? tree;
    double baseline;
    Size size;
    switch (source) {
      case ForumBodyTextBaselineAtomPlan() ||
          ForumBodyIntrinsicInlineAtomPlan():
        _fail(ForumBodyEmphasisGeometryFailure.source);
      case ForumBodyRubyColumnPlan(:final metrics):
        if (metrics == null) _fail(ForumBodyEmphasisGeometryFailure.source);
        _group = metrics;
        baseline = metrics.baseline;
        size = metrics.size;
      case ForumBodyRubySegmentPlan(:final metrics):
        _level = metrics.level;
        baseline = metrics.baseline;
        size = metrics.size;
      case ForumBodyRubySoftSpacePlan(:final metrics):
        _level = metrics.level;
        baseline = metrics.baseline;
        size = metrics.size;
      case ForumBodyRubyTreePlan(:final metrics):
        tree = metrics.root;
        baseline = tree.box.alphabeticBaseline;
        size = tree.frame.size;
      case ForumBodyRubyTreeEmphasisAtomPlan(:final format):
        emphasis = format;
        tree = format.placement.input.input.geometry.metrics.root;
        baseline = format.frame.baseline;
        size = format.frame.size;
    }
    frame = page.rootFonts[_index]?.enclose(
      childSize: size,
      childBaseline: baseline,
    );
    _origin = slot.topLeft + (frame?.childOffset ?? Offset.zero);
    var baseOrigin = _origin;
    if (emphasis != null) {
      _origin += emphasis.frame.childOffset;
      baseOrigin = _origin;
      _decoration = emphasis.placement.input;
      final context = _decoration!.contexts.first;
      _rootRow = context.physicalRow;
      final row = emphasis.placement.rowForId(_rootRow!);
      _overBaseline = row.overBaseline == null
          ? null
          : _origin.dy + row.overBaseline!;
      _underBaseline = row.underBaseline == null
          ? null
          : _origin.dy + row.underBaseline!;
      _overAnnotationMarks = row.overAnnotationMarkerBounds?.shift(_origin);
      _underAnnotationMarks = row.underAnnotationMarkerBounds?.shift(_origin);
      // Direct root reservations also apply when the base has no source leaf.
      _includeEdges(
        _decoration!.nodes.last.localOverEdge == null
            ? null
            : _origin.dy + _decoration!.nodes.last.localOverEdge!,
        _decoration!.nodes.last.localUnderEdge == null
            ? null
            : _origin.dy + _decoration!.nodes.last.localUnderEdge!,
      );
    }
    if (tree != null) {
      baseOrigin += tree.frame.childOffset;
      _group = tree.group;
      _level = tree.segment?.level;
    }
    if (_group case final group?) {
      _top = baseOrigin.dy + group.baseBandTop;
      _bottom = baseOrigin.dy + group.baseBandBottom;
    } else {
      final nativeBaseline =
          baseOrigin.dy + (tree?.segment?.baseline ?? baseline);
      _top = nativeBaseline - _level!.baseAscent;
      _bottom = nativeBaseline + _level!.baseDescent;
      // Retain the actual local anchor for the existing shared stack arithmetic.
      _stackBaseline = nativeBaseline;
      _over = _level!.baseAscent;
      _under = _level!.baseDescent;
    }
    _bandOrigin = baseOrigin.dy;
    _phase = _ChildBandPhase.ranks;
  }

  double _stackBaseline = 0, _bandOrigin = 0;

  void _annotation(int rank) {
    final group = _group;
    double top, bottom;
    ForumBodyRubySide side;
    if (group != null) {
      final band = group.annotations[rank];
      top = _bandOrigin + band.bandTop;
      bottom = _bandOrigin + band.bandBottom;
      side = band.side;
    } else {
      final band = _level!.annotations[rank];
      final next = forumBodyAdvanceRubyBandStack(
        over: _over,
        under: _under,
        hasAnnotation: band.hasAnnotation,
        side: band.side,
        ascent: band.ascent,
        descent: band.descent,
        gap: band.gap,
      );
      _over = next.over;
      _under = next.under;
      top = _stackBaseline + next.top;
      bottom = _stackBaseline + next.bottom;
      side = band.side;
    }
    if (bottom > top) {
      _includeEdges(
        side == ForumBodyRubySide.over ? top : null,
        side == ForumBodyRubySide.under ? bottom : null,
      );
    }
  }

  void _includeEdges(double? over, double? under) {
    if (over != null) {
      _overEdge = _overEdge == null ? over : math.min(_overEdge!, over);
    }
    if (under != null) {
      _underEdge = _underEdge == null ? under : math.max(_underEdge!, under);
    }
  }

  void _clearCurrent() {
    _group = null;
    _level = null;
    _decoration = null;
    _rootRow = null;
    _overEdge = _underEdge = _overBaseline = _underBaseline = null;
    _overAnnotationMarks = _underAnnotationMarks = null;
    _rank = _context = 0;
  }

  static void _check(double value) {
    if (!value.isFinite) _fail(ForumBodyEmphasisGeometryFailure.boxes);
  }

  static Never _fail(ForumBodyEmphasisGeometryFailure failure) =>
      throw ForumBodyEmphasisGeometryException(failure);
  ForumBodyInlineEmphasisChildBands takeBands() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Inline child bands are incomplete');
    final result = _result!;
    close();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Inline child bands are reentrant');
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
    if (_phase == _ChildBandPhase.retired) {
      throw StateError('Inline child bands are retired');
    }
    _ensureOwner!();
    if (_phase == _ChildBandPhase.retired ||
        !_parent!.isActive ||
        _parent!.layout.isDisposed) {
      throw StateError('Inline child band owner is retired');
    }
  }

  void close() {
    _phase = _ChildBandPhase.retired;
    _fonts = null;
    _page = null;
    _parent = null;
    _ensureOwner = null;
    _children = [];
    _result = null;
    _clearCurrent();
  }
}
