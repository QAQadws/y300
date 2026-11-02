import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_text_layout.dart';
import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_emphasis_mark.dart';
import 'forum_body_emphasis_text_geometry.dart';
import 'forum_body_emphasis_text_input.dart';

part 'forum_body_emphasis_line_preparation.dart';

enum ForumBodyEmphasisLineFailure { source, lines, geometry }

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
  });
  final int unitIndex;
  final ForumBodyEmphasisMarkInput input;
  final Offset offset;
  final Rect fontBounds;
  final double fitScale;
}

/// One prepared actual base with source-free decorations. Owns the base source
/// lease and a shared-cache picture; marker font leases retire after recording.
/// Multiline paragraphs require their own row-placement transaction.
final class ForumBodyEmphasisLineLayout implements ForumBodyTextLayout {
  ForumBodyEmphasisLineLayout._({
    required this.input,
    required ForumBodyTextLease base,
    required ForumBodyTextPictureLease picture,
    required this.baseOffset,
    required this.fontBounds,
    required this.width,
    required this.height,
    required this.alphabeticBaseline,
    required List<ForumBodyEmphasisLineMark> marks,
    required void Function() ensureOwner,
  }) : _base = base,
       _picture = picture,
       _ensureOwner = ensureOwner,
       marks = UnmodifiableListView(marks);
  static const revision = 1;
  final ForumBodyEmphasisTextInput input;
  ForumBodyTextLease? _base;
  ForumBodyTextPictureLease? _picture;
  void Function()? _ensureOwner;
  final Offset baseOffset;
  final Rect fontBounds;
  final List<ForumBodyEmphasisLineMark> marks;
  @override
  final double width;
  @override
  final double height;
  @override
  final double alphabeticBaseline;
  @override
  HtmlDisplayTextProjection get projection => input.content.projection;
  @override
  bool get isDisposed => _base?.isActive != true || _picture?.isActive != true;
  @override
  bool get isPaintPrepared => !isDisposed;
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
    return _base!.layout.sourceAt(offset - baseOffset);
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _guard();
    return List.unmodifiable([
      for (final box in _base!.layout.selectionBoxes(startUtf16, endUtf16))
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
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      base?.release();
    }
  }
}
