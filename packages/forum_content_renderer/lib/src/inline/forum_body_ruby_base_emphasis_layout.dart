part of 'forum_body_emphasis_line_layout.dart';

/// Actual original-source binding and final base/marker scene. It claims only
/// the base text, never RT source or full-column readiness. The containing ruby
/// must include bounds in its frame and bind/paint its annotations separately.
final class ForumBodyRubyBaseEmphasisLayout {
  ForumBodyRubyBaseEmphasisLayout._({
    required this.plan,
    required ForumBodyTextLease source,
    required ForumBodyTextPictureLease picture,
    required void Function() ensureOwner,
  }) : _source = source,
       _picture = picture,
       _ensureOwner = ensureOwner;
  final ForumBodyRubyBaseEmphasisPlan plan;
  ForumBodyRubyBaseEmphasisGeometry get geometry => plan.geometry;
  ForumBodyEmphasisTextInput get input => geometry.line.input;
  HtmlDisplayTextProjection get projection => input.content.projection;
  Rect get bounds => geometry.bounds;
  ForumBodyTextLease? _source;
  ForumBodyTextPictureLease? _picture;
  void Function()? _ensureOwner;
  bool get isActive => _source?.isActive == true && _picture?.isActive == true;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_source,
    ?_picture,
  ];
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive && nativeLeases.every(cache.ownsLease);

  void ensureActive() {
    if (!isActive) throw StateError('Ruby emphasis base is retired');
    _ensureOwner!();
    if (!isActive) throw StateError('Ruby emphasis base owner is retired');
  }

  void paint(Canvas canvas, Offset offset) {
    ensureActive();
    _picture!.paint(canvas, offset);
  }

  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    ForumBodyRubyBaseEmphasisMark? selected;
    var nearest = double.infinity;
    for (final placed in geometry.marks) {
      if (!placed.fontBounds.contains(offset)) continue;
      final distance = (placed.fontBounds.center - offset).distanceSquared;
      if (distance < nearest) {
        nearest = distance;
        selected = placed;
      }
    }
    if (selected != null) {
      final unit = input.units[selected.mark.unitIndex];
      final source = projection.sourceAtUtf16(unit.governingUtf16);
      return HtmlProjectedSourcePosition(
        sourceRune: source.sourceRune,
        displayUtf16: source.displayUtf16,
        isExact: false,
      );
    }
    final point = offset - geometry.group.baseOffset;
    final source = _source!.layout.sourceAt(point);
    return geometry.line.baseFontBounds.contains(point)
        ? source
        : HtmlProjectedSourcePosition(
            sourceRune: source.sourceRune,
            displayUtf16: source.displayUtf16,
            isExact: false,
          );
  }

  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    ensureActive();
    final offset = geometry.group.baseOffset;
    return List.unmodifiable([
      for (final box in _source!.layout.selectionBoxes(startUtf16, endUtf16))
        TextBox.fromLTRBD(
          box.left + offset.dx,
          box.top + offset.dy,
          box.right + offset.dx,
          box.bottom + offset.dy,
          box.direction,
        ),
    ]);
  }

  void close() {
    final source = _source, picture = _picture;
    _source = null;
    _picture = null;
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      source?.release();
    }
  }
}
