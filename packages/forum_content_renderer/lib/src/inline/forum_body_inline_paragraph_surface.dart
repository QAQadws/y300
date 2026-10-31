import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show BuildContext, LeafRenderObjectWidget;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_text_surface_box.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_paragraph_view.dart';

/// Takes one fully prepared mixed line view. Each mounted surface needs its
/// own parent/child handles; abandoned unmounted widgets remain caller-owned.
final class ForumBodyInlineParagraphSurface extends LeafRenderObjectWidget {
  const ForumBodyInlineParagraphSurface({
    super.key,
    required this.view,
    this.onSourceTap,
    this.interactionIdentity,
  });
  final ForumBodyInlineParagraphView view;
  final void Function(HtmlProjectedSourcePosition)? onSourceTap;
  final Object? interactionIdentity;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _InlineSurfaceBox(view, onSourceTap, interactionIdentity);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) => (renderObject as _InlineSurfaceBox).configure(
    view,
    onSourceTap,
    interactionIdentity,
  );
}

final class _InlineSurfaceBox extends ForumBodyTextSurfaceBox {
  _InlineSurfaceBox(this._view, super.onTap, super.interactionIdentity);
  ForumBodyInlineParagraphView _view;
  void configure(
    ForumBodyInlineParagraphView view,
    void Function(HtmlProjectedSourcePosition)? onTap,
    Object? interactionIdentity,
  ) {
    final changed = !identical(view, _view);
    if (changed) {
      _view.close();
      _view = view;
    }
    refreshInteraction(
      onTap: onTap,
      interactionIdentity: interactionIdentity,
      geometryChanged: changed,
    );
  }

  @override
  bool get isContentActive => _view.isActive;
  @override
  Size get contentSize =>
      isContentActive ? Size(_view.width, _view.height) : Size.zero;
  @override
  HtmlProjectedSourcePosition sourceAt(Offset position) =>
      _view.sourceAt(position);
  @override
  void paintContent(Canvas canvas, Offset offset) =>
      _view.paint(canvas, offset);
  @override
  void describeContentSemantics(SemanticsConfiguration config) {
    final content = _view.content;
    final text = StringBuffer();
    for (final part in content.projection.display.parts) {
      if (content.runs[part.runIndex].style.visibilityHidden) continue;
      final from = (_view.coverageStartUtf16 - part.utf16Start).clamp(
        0,
        part.text.length,
      );
      final to = (_view.coverageEndUtf16 - part.utf16Start).clamp(
        from,
        part.text.length,
      );
      text.write(part.text.substring(from, to));
    }
    config
      ..isSemanticBoundary = true
      ..textDirection = content.style.textDirection
      ..isHeader = content.style.role == ForumBodyTextRole.heading
      ..label = text.toString();
  }

  @override
  void releaseContent() => _view.close();
}
