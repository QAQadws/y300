import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps account identity at the start and its setting at the end of the row.
class MoreAccountIdentityLayout extends MultiChildRenderObjectWidget {
  MoreAccountIdentityLayout({
    super.key,
    required Widget identity,
    required Widget action,
  }) : super(children: [identity, action]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMoreAccountIdentityLayout(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMoreAccountIdentityLayout).textDirection =
        Directionality.of(context);
  }
}

class _AccountIdentityParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMoreAccountIdentityLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AccountIdentityParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AccountIdentityParentData> {
  _RenderMoreAccountIdentityLayout(this._textDirection);

  static const _spacing = 12.0;

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AccountIdentityParentData) {
      child.parentData = _AccountIdentityParentData();
    }
  }

  Size _layoutSize(
    BoxConstraints constraints,
    Size identitySize,
    Size actionSize,
  ) {
    final contentWidth = identitySize.width + _spacing + actionSize.width;
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : contentWidth;
    final height = contentWidth <= width
        ? math.max(identitySize.height, actionSize.height)
        : identitySize.height + actionSize.height;
    return constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childConstraints = constraints.loosen();
    return _layoutSize(
      constraints,
      firstChild!.getDryLayout(childConstraints),
      lastChild!.getDryLayout(childConstraints),
    );
  }

  @override
  void performLayout() {
    final identity = firstChild!;
    final action = lastChild!;
    final childConstraints = constraints.loosen();
    // Measure the rendered widgets, including text scaling and touch targets,
    // before deciding whether the setting needs its own row.
    identity.layout(childConstraints, parentUsesSize: true);
    action.layout(childConstraints, parentUsesSize: true);
    size = _layoutSize(constraints, identity.size, action.size);
    final fits =
        identity.size.width + _spacing + action.size.width <= size.width;
    final isLtr = _textDirection == TextDirection.ltr;
    (identity.parentData! as _AccountIdentityParentData).offset = Offset(
      isLtr ? 0 : size.width - identity.size.width,
      fits ? size.height - identity.size.height : 0,
    );
    (action.parentData! as _AccountIdentityParentData).offset = Offset(
      isLtr ? size.width - action.size.width : 0,
      fits ? size.height - action.size.height : identity.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
