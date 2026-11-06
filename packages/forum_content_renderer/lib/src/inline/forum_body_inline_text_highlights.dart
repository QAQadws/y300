part of 'forum_body_inline_paragraph_view.dart';

/// Actual leaf commands retain the already-proved placement. A band's ink
/// companion belongs to the original lease's cache entry, not to this replay.
final class _InlineTextHighlights {
  const _InlineTextHighlights(this.steps, this.outlines, this.parent);

  final List<({ForumBodyInlinePaintCommand step, ForumBodyTextLayout? ink})>
  steps;
  final List<({Color color, ForumBodyTextBackgroundGeometry geometry})>
  outlines;
  final _InlineParentHighlights? parent;

  static _InlineTextHighlights? prepare(ForumBodyInlineParagraphView view) {
    final steps =
        <({ForumBodyInlinePaintCommand step, ForumBodyTextLayout? ink})>[];
    final groups = <(String?, Color), List<Rect>>{};
    for (final atom in view._children.keys) {
      for (final step in view.boundAtomPaintCommandsAt(
        view._origin(atom),
        atom,
      )) {
        if (step == null) continue;
        final resource = step.resource;
        final command = step.command;
        ForumBodyTextLayout? ink;
        // A nested scene clip has its own background-plane boundaries. The
        // visible single-level leaf positions have no such inner viewport.
        if (resource is ForumBodyTextLease &&
            resource.content.hasSolidTextBackground &&
            command.clipDepth == 0 &&
            command.fitScale == 1) {
          final regions = forumBodySingleLineBackgroundRegions(
            resource,
          ).toList();
          if (regions.isNotEmpty) {
            ink = forumBodyTryPrepareBackgroundInk(resource);
            if (ink != null) {
              for (final region in regions) {
                (groups[(region.path, region.color)] ??= []).addAll(
                  region.rectangles.map(
                    (rect) => rect.shift(command.sceneOffset),
                  ),
                );
              }
            }
          }
        }
        steps.add((step: step, ink: ink));
      }
    }
    final parent = _InlineParentHighlights.prepare(view);
    if (parent != null) {
      for (final region in parent.regions) {
        (groups[(region.path, region.color)] ??= []).addAll(region.rectangles);
      }
    }
    if (groups.isEmpty) return null;
    try {
      return _InlineTextHighlights(steps, [
        for (final group in groups.entries)
          (
            color: group.key.$2,
            geometry: ForumBodyTextBackgroundGeometry(group.value),
          ),
      ], parent);
    } catch (_) {
      parent?.picture?.release();
      rethrow;
    }
  }

  void paint(
    Canvas canvas,
    Offset offset, {
    required Color? color,
    required double radius,
  }) {
    canvas.save();
    try {
      canvas.translate(offset.dx, offset.dy);
      final paint = Paint();
      for (final outline in outlines) {
        paint.color = color ?? outline.color;
        outline.geometry.paint(canvas, paint, radius);
      }
      parent?.paint(canvas, Offset.zero);
      for (final step in steps) {
        step.step.replay(canvas, textInk: step.ink);
      }
    } finally {
      canvas.restore();
    }
  }

  void close() => parent?.picture?.release();
}
