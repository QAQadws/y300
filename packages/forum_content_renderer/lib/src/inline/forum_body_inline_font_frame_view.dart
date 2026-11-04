part of 'forum_body_inline_paragraph_view.dart';

/// Keeps actual query ownership separate from the parent display list. Both
/// are bound to the same current source before the natural children transfer.
final class _InlineFontFrameBinding {
  _InlineFontFrameBinding(
    this.plan,
    this.startLine,
    this.endLine,
    this.isolated,
    this.picture,
    this.ensureOwner,
  ) : window = plan.fragment(startLine, endLine);
  final ForumBodyInlineFontFramePlan plan;
  final int startLine, endLine;
  final ({
    double top,
    double height,
    int coverageStartUtf16,
    int coverageEndUtf16,
  })
  window;
  final ForumBodyInlineParagraphLease isolated;
  final ForumBodyTextPictureLease picture;
  final void Function() ensureOwner;
  bool get isActive =>
      isolated.isActive && picture.hasSameActiveOwner(isolated);
  void guard() {
    ensureOwner();
    if (!isActive) throw StateError('Allocated inline source is retired');
  }

  ({ForumBodyInlineHit hit, bool isExact}) hitAt(
    Offset point,
    Map<int, _RubyBinding> children,
    Offset Function(int) origin,
  ) {
    guard();
    final absolute = point + Offset(0, window.top), rows = plan.allocation.rows;
    var low = startLine, high = endLine - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (absolute.dy < rows[mid].line.bottom) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final index = low, row = rows[index];
    for (final atom in children.keys) {
      final child = plan.allocation.children[atom]!;
      if (child.lineIndex == index && child.bounds.contains(absolute)) {
        return (
          hit: ForumBodyInlineAtomHit(atom, point - origin(atom)),
          isExact: true,
        );
      }
    }
    final font = plan.allocation.input.geometry.parentFontBounds[index];
    if (font == null || font.isEmpty) {
      return _approximate(row.line.coverageStartUtf16);
    }
    final inverse = absolute - row.logicalOffset;
    final nativePoint = Offset(
      inverse.dx,
      inverse.dy.clamp(font.top, font.bottom - 1e-7),
    );
    final hit = isolated.layout.hitAt(nativePoint);
    if (hit is ForumBodyInlineAtomHit) {
      if (!children.containsKey(hit.index)) {
        return _approximate(row.line.coverageStartUtf16);
      }
      return (
        hit: ForumBodyInlineAtomHit(hit.index, point - origin(hit.index)),
        isExact: false,
      );
    }
    final text = hit as ForumBodyInlineTextHit;
    final bounded = text.position.displayUtf16.clamp(
      row.line.coverageStartUtf16,
      row.line.coverageEndUtf16,
    );
    if (bounded != text.position.displayUtf16) return _approximate(bounded);
    return (hit: text, isExact: nativePoint == inverse);
  }

  ({ForumBodyInlineHit hit, bool isExact}) _approximate(int displayOffset) {
    final position = plan.source.content.projection.display.sourceAtUtf16(
      displayOffset,
    );
    return (
      hit: ForumBodyInlineTextHit(
        HtmlProjectedSourcePosition(
          sourceRune: position.sourceRune,
          displayUtf16: position.displayUtf16,
          isExact: false,
        ),
      ),
      isExact: false,
    );
  }

  TextBox? selectionBox(TextBox box) {
    guard();
    final rect = box.toRect(), physical = plan.allocation.input.rows.rows;
    if (rect.isEmpty) return null;
    // Native selection returns whole physical boxes from the complete source
    // query. Strict strip containment qualifies their row; no source slicing,
    // nearest-row guess or clipping is used to manufacture coverage.
    var low = 0, high = physical.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rect.bottom <= physical[mid].selector.clipBottom) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final strip = physical[low].selector;
    if (rect.top < strip.clipTop || rect.bottom > strip.clipBottom) {
      throw const ForumBodyInlineViewException(
        ForumBodyInlineViewFailure.geometry,
      );
    }
    if (low < startLine || low >= endLine) {
      throw const ForumBodyInlineViewException(
        ForumBodyInlineViewFailure.coverage,
      );
    }
    final placed = rect.shift(
      plan.allocation.rows[low].logicalOffset - Offset(0, window.top),
    );
    return TextBox.fromLTRBD(
      placed.left,
      placed.top,
      placed.right,
      placed.bottom,
      box.direction,
    );
  }

  void close() {
    try {
      picture.release();
    } finally {
      isolated.release();
    }
  }
}
