import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show BuildContext, LeafRenderObjectWidget;
import 'package:forum_content_renderer/forum_text.dart';

import '../style/forum_body_style_options.dart';
import '../style/forum_body_text_background_style.dart';
import 'forum_body_paragraph_background_view.dart';
import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_text_surface_box.dart';

typedef _BackgroundAppearance = ({Color? color, double radius});

/// Paints an already laid out paragraph or line view. This surface takes
/// ownership of one lease; each concurrent surface needs its own lease.
/// The cache remains the reader owner's responsibility. No Widget/Context is
/// retained by it, and late gestures cannot use a replaced or closed lease.
final class ForumBodyParagraphSurface extends LeafRenderObjectWidget {
  const ForumBodyParagraphSurface({
    super.key,
    required this.lease,
    this.startLine = 0,
    this.endLine,
    this.onSourceTap,
    this.interactionIdentity,
  });
  final ForumBodyParagraphLease lease;
  final int startLine;
  final int? endLine;
  final void Function(HtmlProjectedSourcePosition position)? onSourceTap;

  /// Host/layout placement changes retire a gesture even when shaping is shared.
  final Object? interactionIdentity;

  _BackgroundAppearance? _backgroundAppearance(BuildContext context) {
    final style = context
        .dependOnInheritedWidgetOfExactType<ForumBodyTextBackgroundStyle>();
    return style == null || (style.color == null && style.borderRadius == 0)
        ? null
        : (color: style.color, radius: style.borderRadius);
  }

  @override
  RenderBox createRenderObject(BuildContext context) => _ParagraphSurfaceBox(
    lease,
    startLine,
    endLine,
    onSourceTap,
    interactionIdentity,
    _backgroundAppearance(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    (renderObject as _ParagraphSurfaceBox).configure(
      lease,
      startLine,
      endLine,
      onSourceTap,
      interactionIdentity,
      _backgroundAppearance(context),
    );
  }
}

final class _ParagraphSurfaceBox extends ForumBodyTextSurfaceBox {
  _ParagraphSurfaceBox(
    this._lease,
    this._startLine,
    this._endLine,
    void Function(HtmlProjectedSourcePosition)? onTap,
    Object? interactionIdentity,
    this._appearance,
  ) : super(onTap, interactionIdentity) {
    try {
      _view = _makeView(_lease, _startLine, _endLine);
      if (_appearance != null) _prepareBackground();
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  ForumBodyParagraphLease _lease;
  int _startLine;
  int? _endLine;
  ForumBodyParagraphFragment? _view;
  ForumBodyParagraphBackgroundView? _background;
  _BackgroundAppearance? _appearance;

  void _prepareBackground() {
    final view = _view;
    if (view != null && view.coverageStartUtf16 != view.coverageEndUtf16) {
      _background = ForumBodyParagraphBackgroundView.prepare(_lease, view);
    }
  }

  static ForumBodyParagraphFragment? _makeView(
    ForumBodyParagraphLease lease,
    int start,
    int? end,
  ) => !lease.isActive || lease.layout.lines.isEmpty
      ? null
      : lease.layout.fragment(start, end ?? lease.layout.lines.length);

  void configure(
    ForumBodyParagraphLease lease,
    int start,
    int? end,
    void Function(HtmlProjectedSourcePosition)? onTap,
    Object? interactionIdentity,
    _BackgroundAppearance? appearance,
  ) {
    final geometryChanged =
        !identical(_lease, lease) || _startLine != start || _endLine != end;
    var nextView = _view;
    try {
      if (geometryChanged) nextView = _makeView(lease, start, end);
    } catch (_) {
      if (!identical(_lease, lease)) lease.release();
      rethrow;
    }
    if (!identical(_lease, lease)) _lease.release();
    _lease = lease;
    _startLine = start;
    _endLine = end;
    _view = nextView;
    final appearanceChanged = appearance != _appearance;
    _appearance = appearance;
    if (geometryChanged) _background = null;
    if ((geometryChanged || appearanceChanged) &&
        appearance != null &&
        _background == null) {
      _prepareBackground();
    }
    if (appearanceChanged) markNeedsPaint();
    refreshInteraction(
      onTap: onTap,
      interactionIdentity: interactionIdentity,
      geometryChanged: geometryChanged,
    );
  }

  @override
  bool get isContentActive => _lease.isActive;
  @override
  Size get contentSize => !_lease.isActive
      ? Size.zero
      : Size(_lease.layout.width, _view?.height ?? _lease.layout.height);

  @override
  HtmlProjectedSourcePosition sourceAt(Offset position) =>
      _view?.sourceAt(position) ?? _lease.layout.sourceAt(position);
  @override
  void paintContent(Canvas canvas, Offset offset) {
    final appearance = _appearance;
    final background = _background;
    if (appearance != null && background != null) {
      background.paint(
        canvas,
        offset,
        color: appearance.color,
        radius: appearance.radius,
      );
      return;
    }
    final view = _view;
    if (view != null) {
      view.paint(canvas, offset);
    } else {
      _lease.layout.paint(canvas, offset);
    }
  }

  @override
  void describeContentSemantics(SemanticsConfiguration config) {
    final content = _lease.content;
    final start = _view?.startUtf16 ?? 0;
    final end = _view?.endUtf16 ?? content.projection.text.length;
    final text = StringBuffer();
    for (final part in content.projection.parts) {
      if (content.runs[part.runIndex].style.visibilityHidden) continue;
      final from = (start - part.utf16Start).clamp(0, part.text.length);
      final to = (end - part.utf16Start).clamp(from, part.text.length);
      text.write(part.text.substring(from, to));
    }
    config
      ..isSemanticBoundary = true
      ..textDirection = content.style.textDirection
      ..isHeader = content.style.role == ForumBodyTextRole.heading
      ..label = text.toString();
  }

  @override
  void releaseContent() {
    _background = null;
    _lease.release();
  }
}
