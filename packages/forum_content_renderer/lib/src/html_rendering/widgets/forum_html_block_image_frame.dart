import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A width-filling block image frame whose geometry belongs to [aspectRatio].
///
/// Loading, error and decoded content have no preferred pixel size or text
/// baseline. In particular, an unbounded intrinsic query must not establish a
/// layout dependency on those transient children. Zero matches the existing
/// layout-builder image path when no finite opposite dimension is available.
class ForumHtmlBlockImageFrame extends SingleChildRenderObjectWidget {
  const ForumHtmlBlockImageFrame({
    super.key,
    required this.aspectRatio,
    required super.child,
  }) : assert(aspectRatio > 0),
       assert(aspectRatio < double.infinity);

  final double aspectRatio;

  @override
  RenderAspectRatio createRenderObject(BuildContext context) =>
      _RenderBlockImageFrame(aspectRatio: aspectRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAspectRatio renderObject,
  ) {
    renderObject.aspectRatio = aspectRatio;
  }
}

class _RenderBlockImageFrame extends RenderAspectRatio {
  _RenderBlockImageFrame({required super.aspectRatio});

  @override
  double computeMinIntrinsicWidth(double height) =>
      height.isFinite ? height * aspectRatio : 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      height.isFinite ? height * aspectRatio : 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      width.isFinite ? width / aspectRatio : 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      width.isFinite ? width / aspectRatio : 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => null;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => null;
}
