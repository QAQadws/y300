import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_annotation_input.dart';
import 'forum_body_ruby_content.dart';

/// A single original annotation box and the half-open base-column interval it
/// owns. Source, styles and text identity stay with that ONE box across a span.
final class ForumBodyRubyAnnotationSpan {
  const ForumBodyRubyAnnotationSpan._({
    required this.box,
    required this.startColumn,
    required this.endColumn,
  });
  final ForumBodyRubyAnnotationBoxInput box;
  final int startColumn;
  final int endColumn;
  bool get isMultiColumn => endColumn - startColumn > 1;
}

final class ForumBodyRubyPairedAnnotationLevel {
  ForumBodyRubyPairedAnnotationLevel._({
    required this.side,
    required List<ForumBodyRubyAnnotationSpan> spans,
  }) : spans = List.unmodifiable(spans);
  final ForumBodyRubySide side;
  final List<ForumBodyRubyAnnotationSpan> spans;
}

/// Pure unit pairing after anonymous-box generation, before glyph measurement.
/// Empty/missing positions are not invented source boxes. An entire segment's
/// base count includes anonymous bases needed by any longer annotation level.
final class ForumBodyRubyAnnotationPairing {
  factory ForumBodyRubyAnnotationPairing({
    required ForumBodyRubyGroupContent group,
    required int baseColumnCount,
  }) {
    if (baseColumnCount < 0) {
      throw ArgumentError.value(baseColumnCount, 'baseColumnCount');
    }
    final inputs = resolveForumBodyRubyAnnotationInputs(group);
    var columnCount = baseColumnCount;
    for (final level in inputs) {
      if (level.boxes.length > columnCount) columnCount = level.boxes.length;
    }
    var annotatedColumnCount = 0;
    var hasMultiColumnSpans = false;
    final levels = <ForumBodyRubyPairedAnnotationLevel>[];
    for (final level in inputs) {
      final spans = <ForumBodyRubyAnnotationSpan>[];
      final spansSegment =
          level.boxes.length == 1 &&
          level.boxes.single is ForumBodyRubyAnonymousAnnotationInput;
      for (final (index, box) in level.boxes.indexed) {
        final end = spansSegment ? columnCount : index + 1;
        if (end > annotatedColumnCount) annotatedColumnCount = end;
        final span = ForumBodyRubyAnnotationSpan._(
          box: box,
          startColumn: index,
          endColumn: end,
        );
        hasMultiColumnSpans |= span.isMultiColumn;
        spans.add(span);
      }
      levels.add(
        ForumBodyRubyPairedAnnotationLevel._(side: level.side, spans: spans),
      );
    }
    return ForumBodyRubyAnnotationPairing._(
      columnCount: columnCount,
      annotatedColumnCount: annotatedColumnCount,
      levels: levels,
      hasMultiColumnSpans: hasMultiColumnSpans,
    );
  }

  ForumBodyRubyAnnotationPairing._({
    required this.columnCount,
    required this.annotatedColumnCount,
    required List<ForumBodyRubyPairedAnnotationLevel> levels,
    required this.hasMultiColumnSpans,
  }) : levels = List.unmodifiable(levels);

  final int columnCount;
  final int annotatedColumnCount;
  final List<ForumBodyRubyPairedAnnotationLevel> levels;
  final bool hasMultiColumnSpans;
}
