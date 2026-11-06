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
  });
  final int atomIndex, lineIndex;
  final ForumBodyRubyAtomPlan source;

  /// Root glyph coordinates translated to the actual parent's paint plane.
  /// This never translates DOM/display/semantic source coordinates.
  final Offset glyphOrigin;
  final double baseTop, baseBottom;

  /// Font-only annotation reservations, including existing virtual empty RTs.
  final double? overEdge, underEdge;
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

enum _ChildBandPhase { atoms, ranks, finish, publish, ready, retired }

/// Reads final aligned child geometry one atom or annotation rank at a time.
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
  int _index = 0, _rank = 0;
  double _top = 0, _bottom = 0, _over = 0, _under = 0;
  double? _overEdge, _underEdge;
  Offset _origin = Offset.zero;
  ForumBodyRubyGroupMetrics? _group;
  ForumBodyRubyLevelMetrics? _level;
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
              _phase = _ChildBandPhase.finish;
            }

          case _ChildBandPhase.finish:
            _check(_top);
            _check(_bottom);
            if (_top > _bottom) _fail(ForumBodyEmphasisGeometryFailure.boxes);
            for (final value in [_overEdge, _underEdge]) {
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
    ForumBodyRubyTreeContainerMetrics? tree;
    double baseline;
    Size size;
    switch (source) {
      case ForumBodyInlineImageAtomPlan(:final input):
        _neutralFrame(
          slot,
          input.dimensions.size,
          input.dimensions.baselineOffset!,
        );
        return;
      case ForumBodyTextBaselineAtomPlan(:final metrics):
        _neutralFrame(slot, metrics.size, metrics.baseline);
        return;
      case ForumBodyIntrinsicInlineAtomPlan(:final metrics):
        _neutralFrame(slot, metrics.size, metrics.baseline);
        return;
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
    }
    frame = page.rootFonts[_index]?.enclose(
      childSize: size,
      childBaseline: baseline,
    );
    _origin = slot.topLeft + (frame?.childOffset ?? Offset.zero);
    var baseOrigin = _origin;
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

  void _neutralFrame(Rect slot, Size size, double baseline) {
    final page = _page!, dimension = page.dimensions[_index];
    // Sup/sub and intrinsic words already enclose their own font bounds. Only
    // mark-free row allocation borrows that frame; annotation/mark placement
    // cannot infer ruby bands from an ordinary text box.
    if (_fonts!.geometry.input.units.isNotEmpty ||
        page.rootFonts[_index] != null ||
        dimension.size != size ||
        dimension.baselineOffset != baseline) {
      _fail(ForumBodyEmphasisGeometryFailure.source);
    }
    _origin = slot.topLeft;
    _top = slot.top;
    _bottom = slot.bottom;
    _phase = _ChildBandPhase.finish;
  }

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
    _overEdge = _underEdge = null;
    _rank = 0;
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
