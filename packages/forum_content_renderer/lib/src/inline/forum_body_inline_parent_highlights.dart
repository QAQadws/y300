part of 'forum_body_inline_paragraph_view.dart';

/// The parent contributes only its ordinary text. Atomic children keep their
/// own original draw commands, typography and sources.
final class _InlineParentHighlights {
  const _InlineParentHighlights(this.regions, this.paint, this.picture);

  final List<ForumBodyTextBackgroundRegion> regions;
  final void Function(Canvas, Offset) paint;
  final ForumBodyTextPictureLease? picture;

  static _InlineParentHighlights? prepare(ForumBodyInlineParagraphView view) {
    final natural = view._parent!;
    final content = natural.content;
    if (!content.hasSolidParentTextBackground) return null;
    final frames = view._fontFrames;
    final native = frames?.isolated ?? natural;
    final layout = native.layout;
    final regions = forumBodyLineBackgroundRegions(
      runs: content.parentTextRanges,
      scaler: native.capturedTextScaler,
      lines: layout.lines,
      startLine: view.startLine,
      endLine: view.endLine,
      selectionBoxes: (start, end) =>
          layout.glyphSelection(start, end).textBoxes,
      placeRow: (row) =>
          (frames?.plan.allocation.rows[row].logicalOffset ?? Offset.zero) -
          Offset(0, frames?.window.top ?? view._fragment!.top),
    ).toList();
    if (regions.isEmpty) return null;
    try {
      if (frames == null) {
        final ink = natural.prepareNaturalTextBackgroundInk();
        final window = ink.fragment(view.startLine, view.endLine);
        return _InlineParentHighlights(regions, window.paintParent, null);
      }
      if (frames.picture == null) return null;
      final ink = _recordParentInk(frames);
      return ink == null
          ? null
          : _InlineParentHighlights(regions, ink.paint, ink);
    } on ForumBodyParagraphBudgetException {
      return null;
    } on ForumBodyParagraphLayoutException catch (error) {
      if (error.failure != ForumBodyParagraphLayoutFailure.coverage) rethrow;
      return null;
    }
  }

  static ForumBodyTextPictureLease? _recordParentInk(
    _InlineFontFrameBinding frames,
  ) {
    frames.guard();
    final cache = frames.cache;
    final plan = frames.plan;
    var reference = plan.paintReference;
    final parents = <ForumBodyInlineParagraphLease>[];
    ForumBodyInlineEmphasisPaintBinding? restored;
    try {
      for (final index in [1, 2]) {
        final phase = reference.requests[index].acquire(
          cache,
          width: plan.allocation.input.natural.requestWidth,
          textScaler: plan.textScaler,
          cachedOnly: true,
        );
        if (phase == null) break;
        if (!phase.hasSameActiveOwner(frames.isolated) ||
            phase.nativeInputIdentity !=
                reference.phaseInputIdentities[index] ||
            !identical(phase.layout.lines, reference.phaseLines[index])) {
          phase.release();
          break;
        }
        parents.add(phase);
      }
      if (parents.length != 2) {
        for (final parent in parents) {
          parent.release();
        }
        parents.clear();
        // Eviction can remove an unpinned phase while its recorded default
        // picture remains visible. Reuse the same source qualification.
        final preparation = ForumBodyInlineEmphasisPaintPreparation(
          allocation: plan.allocation,
          source: frames.isolated,
          cache: cache,
          expectedTextScaler: plan.textScaler,
          ensureOwner: frames.guard,
        );
        try {
          while (!preparation.isReady) {
            if (preparation.advance().waitingForLayoutBudget) return null;
          }
          restored = preparation.takeBinding();
          reference = restored.view.reference;
          parents.addAll(restored.phases.skip(1));
        } finally {
          preparation.close();
        }
      }
      for (final parent in parents) {
        cache.prepareInlineParentPaint(parent);
      }
      final rows = [
        for (var line = frames.startLine; line < frames.endLine; line++)
          for (final (index, layer) in const [
            ForumBodyParagraphPaintLayer.foreground,
            ForumBodyParagraphPaintLayer.decoration,
          ].indexed)
            ForumBodyInlinePaintRowView.phase(
              parent: parents[index],
              reference: reference,
              lineIndex: line,
              layer: layer,
              ensureOwner: frames.guard,
              allocationOrigin: Offset(0, -frames.window.top),
            ),
      ].where((row) => !row.selector.isEmpty).toList();
      if (rows.isEmpty) return null;
      final preparation = ForumBodyTextPicturePreparation(
        cache: cache,
        input: ForumBodyTextPictureInput(
          maxCommands: ForumBodyTextPictureInput.maximumCommands,
          commands: [
            for (final row in rows)
              ForumBodyTextPictureCommand.fromInlineRow(row, Offset.zero),
          ],
        ),
        text: const [],
        inlineRows: rows,
        ensureOwner: frames.guard,
      );
      try {
        while (!preparation.isReady) {
          if (preparation.advance().waitingForLayoutBudget) return null;
        }
        return preparation.takeLease();
      } finally {
        preparation.close();
      }
    } finally {
      if (restored != null) {
        restored.close();
      } else {
        for (final parent in parents) {
          parent.release();
        }
      }
    }
  }
}
