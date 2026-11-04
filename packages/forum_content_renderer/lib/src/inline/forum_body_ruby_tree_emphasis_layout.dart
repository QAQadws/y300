part of 'forum_body_emphasis_line_layout.dart';

/// Current original-source glyph binding plus the whole tree's shared marker
/// scene. Source windows stay separate; a containing page must still bind each
/// actual original/DOM context before claiming page or canonical coverage.
final class ForumBodyRubyTreeEmphasisLayout {
  ForumBodyRubyTreeEmphasisLayout._({
    required this.plan,
    required ForumBodyRubyGlyphTreeBinding glyphs,
    required ForumBodyTextPictureLease? picture,
    required List<({Rect rect, ForumBodyRubyContainerFontBox font})>
    backgrounds,
    required void Function() ensureOwner,
  }) : _glyphs = glyphs,
       _picture = picture,
       sources = glyphs.sources,
       backgrounds = UnmodifiableListView(backgrounds),
       _ensureOwner = ensureOwner;
  final ForumBodyRubyTreeEmphasisPlan plan;
  final List<ForumBodyRubyGlyphTreeBoundSource> sources;
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})> backgrounds;
  ForumBodyRubyGlyphTreeBinding? _glyphs;
  ForumBodyTextPictureLease? _picture;
  void Function()? _ensureOwner;
  Size get size => plan.frame.size;
  double get baseline => plan.frame.baseline;
  Offset get contentOffset => plan.frame.childOffset;
  bool get isActive =>
      _glyphs?.isActive == true &&
      (plan.markerPictureInput == null || _picture?.isActive == true);
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    yield* _glyphs?.nativeLeases ?? const [];
    if (_picture case final picture?) yield picture;
  }

  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive && nativeLeases.every(cache.ownsLease);
  void ensureActive() {
    if (!isActive) throw StateError('Ruby tree emphasis is retired');
    _ensureOwner!();
    if (!isActive) throw StateError('Ruby tree emphasis owner is retired');
  }

  ForumBodyRubyGlyphTreeBoundSource sourceForId(int id) {
    ensureActive();
    return _glyphs!.sourceForId(id);
  }

  /// Backgrounds are a separate prepared plane so a containing page can paint
  /// every background before any glyph, including alpha/nested containers.
  void paintBackgrounds(Canvas canvas, Offset offset, {required Rect clip}) {
    ensureActive();
    canvas.save();
    try {
      canvas.clipRect(clip);
      for (final surface in backgrounds) {
        canvas.drawRect(
          surface.rect.shift(offset),
          Paint()..color = surface.font.background.color,
        );
      }
    } finally {
      canvas.restore();
    }
  }

  void paint(Canvas canvas, Offset offset) {
    ensureActive();
    canvas.save();
    try {
      canvas.translate(offset.dx, offset.dy);
      canvas.translate(contentOffset.dx, contentOffset.dy);
      _glyphs!.paintGlyphs(canvas, Offset.zero);
      _picture?.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }

  Iterable<ForumBodyInlinePaintCommand?> paintCommands(Offset offset) sync* {
    final glyphs = _glyphs;
    if (glyphs == null) throw StateError('Ruby tree emphasis is retired');
    void check() {
      _ensureOwner?.call();
      if (!identical(_glyphs, glyphs)) {
        throw StateError('Ruby tree emphasis owner is retired');
      }
    }

    check();
    for (final step in glyphs.paintCommands(Offset.zero)) {
      check();
      // These are two REAL Canvas translations in paint(), unlike ancestor
      // frame/member offsets added in Dart before the call.
      yield step?.translated(contentOffset).translated(offset);
    }
    if (_picture case final picture?) {
      yield ForumBodyInlinePaintCommand.picture(
        picture,
        Offset.zero,
      ).translated(contentOffset).translated(offset);
    }
    check();
  }

  ForumBodyRubyTreeHit sourceAt(Offset offset) {
    ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    final point = offset - contentOffset;
    ForumBodyRubyTreePlacedEmphasisMark? selected;
    var distance = double.infinity;
    for (final mark in plan.placement.marks) {
      if (!mark.fontBounds.contains(point)) continue;
      final candidate = (mark.fontBounds.center - point).distanceSquared;
      if (candidate < distance) {
        selected = mark;
        distance = candidate;
      }
    }
    if (selected != null) {
      final source = selected.source.source.source;
      final unit = selected.source.line.input.units[selected.mark.unitIndex];
      final position = source.content.projection.sourceAtUtf16(
        unit.governingUtf16,
      );
      return (
        nodeIndex: source.id,
        content: source.content,
        position: HtmlProjectedSourcePosition(
          sourceRune: position.sourceRune,
          displayUtf16: position.displayUtf16,
          isExact: false,
        ),
      );
    }
    return _glyphs!.sourceAtGlyph(point);
  }

  List<TextBox> selectionBoxes({
    required int sourceId,
    required int startUtf16,
    required int endUtf16,
    bool paintedOnly = false,
  }) {
    ensureActive();
    final shift = contentOffset;
    return [
      for (final box in _glyphs!.glyphSelectionBoxes(
        sourceId: sourceId,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        paintedOnly: paintedOnly,
      ))
        TextBox.fromLTRBD(
          box.left + shift.dx,
          box.top + shift.dy,
          box.right + shift.dx,
          box.bottom + shift.dy,
          box.direction,
        ),
    ];
  }

  void close() {
    final glyphs = _glyphs, picture = _picture;
    _glyphs = null;
    _picture = null;
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      glyphs?.close();
    }
  }
}
