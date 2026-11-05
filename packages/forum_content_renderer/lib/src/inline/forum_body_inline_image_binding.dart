part of 'forum_body_inline_paragraph_view.dart';

/// Source-bound visible resource placement, separate from glyph coverage and
/// native handle cost. Pixel readiness is transient and belongs to this view.
final class ForumBodyInlineImageBinding {
  ForumBodyInlineImageBinding._(
    this.input,
    this.atomIndex,
    this.lineIndex,
    this.rect,
    this._parent,
  );
  final ForumBodyInlineImageInput input;
  final int atomIndex, lineIndex;
  final Rect rect;
  final ForumBodyInlineParagraphLease _parent;
  bool _retired = false, _hasFrame = false;
  bool get isActive =>
      !_retired && _parent.isActive && !_parent.layout.isDisposed;
  bool get hasRenderedFrame => isActive && _hasFrame;
  bool reportDisplayFrame(bool rendered) {
    if (!isActive || _hasFrame == rendered) return false;
    _hasFrame = rendered;
    return true;
  }

  void _retire() {
    _retired = true;
    _hasFrame = false;
  }
}
