import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show BuildContext, LeafRenderObjectWidget;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_layout.dart';

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

  @override
  RenderBox createRenderObject(BuildContext context) => _ParagraphSurfaceBox(
    lease,
    startLine,
    endLine,
    onSourceTap,
    interactionIdentity,
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
    );
  }
}

final class _ParagraphSurfaceBox extends RenderBox {
  _ParagraphSurfaceBox(
    this._lease,
    this._startLine,
    this._endLine,
    this._onTap,
    this._interactionIdentity,
  ) {
    try {
      _view = _makeView(_lease, _startLine, _endLine);
      _createRecognizer();
    } catch (_) {
      _lease.release();
      rethrow;
    }
  }
  ForumBodyParagraphLease _lease;
  int _startLine;
  int? _endLine;
  void Function(HtmlProjectedSourcePosition)? _onTap;
  Object? _interactionIdentity;
  ForumBodyParagraphFragment? _view;
  late TapGestureRecognizer _tap;

  void _createRecognizer() {
    _tap = TapGestureRecognizer()
      ..onTapUp = (details) {
        if (!attached || !_lease.isActive) return;
        final position =
            _view?.sourceAt(details.localPosition) ??
            _lease.layout.sourceAt(details.localPosition);
        _onTap?.call(position);
      };
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
  ) {
    _onTap = onTap;
    final geometryChanged =
        !identical(_lease, lease) || _startLine != start || _endLine != end;
    if (!geometryChanged && _interactionIdentity == interactionIdentity) {
      return;
    }
    var nextView = _view;
    try {
      if (geometryChanged) nextView = _makeView(lease, start, end);
    } catch (_) {
      if (!identical(_lease, lease)) lease.release();
      rethrow;
    }
    _tap.dispose();
    _createRecognizer();
    if (!identical(_lease, lease)) _lease.release();
    _lease = lease;
    _startLine = start;
    _endLine = end;
    _interactionIdentity = interactionIdentity;
    _view = nextView;
    if (geometryChanged) {
      markNeedsLayout();
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  Size get _contentSize => !_lease.isActive
      ? Size.zero
      : Size(_lease.layout.width, _view?.height ?? _lease.layout.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (!_lease.isActive) return constraints.smallest;
    final contentSize = _contentSize;
    final result = constraints.constrain(contentSize);
    if (result.width != contentSize.width ||
        result.height < contentSize.height) {
      throw FlutterError(
        'Paragraph surface constraints do not match its layout',
      );
    }
    return result;
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _contentSize.width;
  @override
  double computeMaxIntrinsicWidth(double height) => _contentSize.width;
  @override
  double computeMinIntrinsicHeight(double width) => _contentSize.height;
  @override
  double computeMaxIntrinsicHeight(double width) => _contentSize.height;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_lease.isActive) return;
    final view = _view;
    if (view != null) {
      view.paint(context.canvas, offset);
    } else {
      _lease.layout.paint(context.canvas, offset);
    }
  }

  @override
  bool hitTestSelf(Offset position) => _onTap != null && _lease.isActive;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent && _onTap != null && _lease.isActive) {
      _tap.addPointer(event);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (!_lease.isActive) return;
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
  void detach() {
    _tap.dispose();
    _createRecognizer();
    super.detach();
  }

  @override
  void dispose() {
    _tap.dispose();
    _lease.release();
    super.dispose();
  }
}
