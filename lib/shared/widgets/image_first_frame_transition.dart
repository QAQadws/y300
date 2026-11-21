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
  bool fadeInOnCacheHit = false,
}) {
  final visibleChild = isResolved ? child : placeholder;
  if (duration <= Duration.zero || MediaQuery.disableAnimationsOf(context)) {
    return visibleChild;
  }
  if (fadeInOnCacheHit) {
    if (!isResolved) return placeholder;
    // An already decoded image may be ready on the first build, when an
    // AnimatedSwitcher would have no outgoing child to animate from.
    return TweenAnimationBuilder<double>(
      key: ValueKey(identity),
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, opacity, image) => Stack(
        fit: StackFit.passthrough,
        children: [
          if (opacity < 1) Positioned.fill(child: placeholder),
          Opacity(opacity: opacity, child: image),
        ],
      ),
      child: child,
    );
  }
  if (wasSynchronouslyLoaded) {
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
