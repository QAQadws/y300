import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_text_surface_box.dart';
import '../style/forum_body_style_options.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import '../html_rendering/widgets/forum_html_image_view.dart';
import '../services/forum_html_image_anchor_controller.dart';
import 'forum_body_inline_paragraph_view.dart';

part 'forum_body_inline_image_surface.dart';

/// Owns a prepared text/ruby view. Image-bearing views use the image Surface,
/// which supplies its current Host and mounts the separate resource plane.
final class ForumBodyInlineParagraphSurface extends LeafRenderObjectWidget {
  const ForumBodyInlineParagraphSurface({
    super.key,
    required this.view,
    this.onSourceTap,
    this.interactionIdentity,
    this.paintBackgrounds = true,
  }) : _allowsImages = false;
  const ForumBodyInlineParagraphSurface._imageTextLayer({
    required this.view,
    this.onSourceTap,
    this.interactionIdentity,
    this.paintBackgrounds = true,
  }) : _allowsImages = true;
  final bool _allowsImages;
  final ForumBodyInlineParagraphView view;
  final void Function(HtmlProjectedSourcePosition)? onSourceTap;
  final Object? interactionIdentity;
  final bool paintBackgrounds;
  @override
  RenderBox createRenderObject(BuildContext context) {
    _validateImages();
    return _InlineSurfaceBox(
      view,
      onSourceTap,
      interactionIdentity,
      paintBackgrounds,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    _validateImages();
    (renderObject as _InlineSurfaceBox).configure(
      view,
      onSourceTap,
      interactionIdentity,
      paintBackgrounds,
    );
  }

  void _validateImages() {
    if (!_allowsImages && view.images.isNotEmpty) {
      throw const ForumBodyInlineViewException(
        ForumBodyInlineViewFailure.coverage,
      );
    }
  }
}

final class _InlineSurfaceBox extends ForumBodyTextSurfaceBox {
  _InlineSurfaceBox(
    this._view,
    super.onTap,
    super.interactionIdentity,
    this._paintBackgrounds,
  );
  ForumBodyInlineParagraphView _view;
  bool _paintBackgrounds;
  void configure(
    ForumBodyInlineParagraphView view,
    void Function(HtmlProjectedSourcePosition)? onTap,
    Object? interactionIdentity,
    bool paintBackgrounds,
  ) {
    final changed = !identical(view, _view);
    if (_paintBackgrounds != paintBackgrounds) markNeedsPaint();
    _paintBackgrounds = paintBackgrounds;
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
  Rect get paintBounds => isContentActive && _paintBackgrounds
      ? _view.paintBounds
      : super.paintBounds;
  @override
  Size get contentSize =>
      isContentActive ? Size(_view.width, _view.height) : Size.zero;
  @override
  HtmlProjectedSourcePosition sourceAt(Offset position) =>
      _view.sourceAt(position);
  @override
  bool hitTestSelf(Offset position) =>
      super.hitTestSelf(position) && _view.imageAt(position) == null;
  @override
  void paintContent(Canvas canvas, Offset offset) =>
      _view.paintTextLayer(canvas, offset, paintBackgrounds: _paintBackgrounds);
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
