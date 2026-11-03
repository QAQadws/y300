import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_geometry.dart'
    show forumBodyPaintedTextRanges;
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_paragraph_line_frames.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import '../paragraph/forum_body_text_layout.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_emphasis_mark.dart';
import 'forum_body_emphasis_mark_request.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_emphasis_text_input.dart';
import 'forum_body_emphasis_row_input.dart';
import 'forum_body_emphasis_row_allocation.dart';
import 'forum_body_emphasis_paragraph_metrics.dart';

part 'forum_body_emphasis_line_preparation.dart';
part 'forum_body_emphasis_line_metrics.dart';
part 'forum_body_emphasis_allocated_layout.dart';
part 'forum_body_emphasis_allocated_preparation.dart';
part 'forum_body_emphasis_allocated_scene_input.dart';
part 'forum_body_emphasis_fragment_layout.dart';
part 'forum_body_emphasis_fragment_preparation.dart';

enum ForumBodyEmphasisLineFailure { source, lines, geometry, metrics }

final class ForumBodyEmphasisLineException implements Exception {
  const ForumBodyEmphasisLineException(this.failure);
  final ForumBodyEmphasisLineFailure failure;
  @override
  String toString() => 'ForumBodyEmphasisLineException(${failure.name})';
}

/// Numeric decoration placement only. Its source unit stays in the original
/// input; the marker itself contributes no display/copy or semantic coordinate.
final class ForumBodyEmphasisLineMark {
  const ForumBodyEmphasisLineMark._({
    required this.unitIndex,
    required this.input,
    required this.offset,
    required this.fontBounds,
    required this.fitScale,
    required this.lineIndex,
  });
  final int unitIndex;
  final ForumBodyEmphasisMarkInput input;
  final Offset offset;
  final Rect fontBounds;
  final double fitScale;

  /// Actual governing physical row in this component's source context.
  final int lineIndex;
}

/// One prepared actual base with source-free decorations. Owns the base source
/// lease and a shared-cache picture; marker font leases retire after recording.
/// An explicit row-group input retains its actual physical rows and source
/// window. An ordinary paragraph input must still be genuinely single-line.
final class ForumBodyEmphasisLineLayout implements ForumBodyTextLayout {
  ForumBodyEmphasisLineLayout._({
    required this.metrics,
    required ForumBodyTextLease base,
    required ForumBodyTextPictureLease picture,
    required void Function() ensureOwner,
    ForumBodyParagraphRowView? row,
  }) : _base = base,
       _picture = picture,
       _row = row,
       _ensureOwner = ensureOwner;
  static const revision = 2;
  final ForumBodyEmphasisLineMetrics metrics;
  ForumBodyEmphasisTextInput get input => metrics.input;
  ForumBodyTextLease? _base;
  ForumBodyTextPictureLease? _picture;
  ForumBodyParagraphRowView? _row;
  void Function()? _ensureOwner;
  Offset get baseOffset => metrics.baseOffset;
  Rect get fontBounds => metrics.fontBounds;
  List<ForumBodyEmphasisLineMark> get marks => metrics.marks;
  @override
  double get width => metrics.width;
  @override
  double get height => metrics.height;
  @override
  double get alphabeticBaseline => metrics.alphabeticBaseline;
  @override
  HtmlDisplayTextProjection get projection => input.content.projection;
  @override
  bool get isDisposed => _base?.isActive != true || _picture?.isActive != true;
  @override
  bool get isPaintPrepared => !isDisposed;
  void ensureActive() => _guard();
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_base,
    ?_picture,
  ];

  void _guard() {
    if (isDisposed) throw StateError('Emphasis line is retired');
    _ensureOwner!();
    if (isDisposed) throw StateError('Emphasis line owner is retired');
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    _guard();
    _picture!.paint(canvas, offset);
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _guard();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    ForumBodyEmphasisLineMark? selected;
    var distance = double.infinity;
    for (final mark in marks) {
      if (!mark.fontBounds.contains(offset)) continue;
      final current = (mark.fontBounds.center - offset).distanceSquared;
      if (current < distance) {
        selected = mark;
        distance = current;
      }
    }
    if (selected != null) {
      final unit = input.units[selected.unitIndex];
      final source = projection.sourceAtUtf16(unit.governingUtf16);
      return HtmlProjectedSourcePosition(
        sourceRune: source.sourceRune,
        displayUtf16: source.displayUtf16,
        isExact: false,
      );
    }
    return (_row ?? _base!.layout).sourceAt(offset - baseOffset);
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _guard();
    return List.unmodifiable([
      for (final box in (_row ?? _base!.layout).selectionBoxes(
        startUtf16,
        endUtf16,
      ))
        TextBox.fromLTRBD(
          box.left + baseOffset.dx,
          box.top + baseOffset.dy,
          box.right + baseOffset.dx,
          box.bottom + baseOffset.dy,
          box.direction,
        ),
    ]);
  }

  void close() {
    final base = _base, picture = _picture;
    _base = null;
    _picture = null;
    _row = null;
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      base?.release();
    }
  }
}
