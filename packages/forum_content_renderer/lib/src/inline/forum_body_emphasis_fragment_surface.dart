import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show BuildContext, LeafRenderObjectWidget;
import 'package:forum_content_renderer/forum_text.dart';

import '../paragraph/forum_body_text_surface_box.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_frame.dart' show ForumBodyEmphasisFragmentLayout;

/// Owns one fully prepared source/scene view. Visible paint only replays it;
/// each concurrent mount needs its own two handles, even for a shared picture.
final class ForumBodyEmphasisFragmentSurface extends LeafRenderObjectWidget {
  const ForumBodyEmphasisFragmentSurface({
    super.key,
    required this.view,
    this.onSourceTap,
    this.interactionIdentity,
  });
  final ForumBodyEmphasisFragmentLayout view;
  final void Function(HtmlProjectedSourcePosition)? onSourceTap;
  final Object? interactionIdentity;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _EmphasisSurfaceBox(view, onSourceTap, interactionIdentity);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) => (renderObject as _EmphasisSurfaceBox).configure(
    view,
    onSourceTap,
    interactionIdentity,
  );
}

final class _EmphasisSurfaceBox extends ForumBodyTextSurfaceBox {
  _EmphasisSurfaceBox(this._view, super.onTap, super.interactionIdentity) {
    try {
      _view.ensureActive();
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  ForumBodyEmphasisFragmentLayout _view;
  void configure(
    ForumBodyEmphasisFragmentLayout view,
    void Function(HtmlProjectedSourcePosition)? onTap,
    Object? interactionIdentity,
  ) {
    final changed = !identical(view, _view);
    try {
      view.ensureActive();
    } catch (_) {
      if (changed) view.close();
      rethrow;
    }
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
  bool get isContentActive => !_view.isDisposed;
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
    _describeSemantics(
      config,
      _view.input.paragraph.content,
      _view.coverageStartUtf16,
      _view.coverageEndUtf16,
    );
  }

  @override
  void releaseContent() => _view.close();
}

void _describeSemantics(
  SemanticsConfiguration config,
  ForumBodyParagraphContent content,
  int start,
  int end,
) {
  final text = StringBuffer();
  for (final part in content.projection.parts) {
    if (content.runs[part.runIndex].style.visibilityHidden) continue;
    final from = (start - part.utf16Start).clamp(0, part.text.length),
        to = (end - part.utf16Start).clamp(from, part.text.length);
    text.write(part.text.substring(from, to));
  }
  config
    ..isSemanticBoundary = true
    ..textDirection = content.style.textDirection
    ..isHeader = content.style.role == ForumBodyTextRole.heading
    ..label = text.toString();
}

/// A fully prepared single native source context. Its base and marks already
/// share the actual fitted paint scale; the visible render object only replays.
