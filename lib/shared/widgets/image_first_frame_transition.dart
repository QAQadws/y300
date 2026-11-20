import 'package:flutter/material.dart';

/// Keeps the placeholder visible until the image can paint its first frame.
Widget buildImageFirstFrameTransition(
  BuildContext context, {
  required Widget child,
  required Widget placeholder,
  required bool isResolved,
  required bool wasSynchronouslyLoaded,
  required Duration duration,
  required Object identity,
}) {
  final visibleChild = isResolved ? child : placeholder;
  if (wasSynchronouslyLoaded ||
      duration <= Duration.zero ||
      MediaQuery.disableAnimationsOf(context)) {
    return visibleChild;
  }
  return AnimatedSwitcher(
    duration: duration,
    reverseDuration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeOutCubic,
    layoutBuilder: (currentChild, previousChildren) => Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: <Widget>[...previousChildren, ?currentChild],
    ),
    child: KeyedSubtree(
      key: ValueKey((identity, isResolved)),
      child: visibleChild,
    ),
  );
}
