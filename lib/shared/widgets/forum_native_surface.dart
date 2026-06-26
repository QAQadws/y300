import 'package:flutter/material.dart';

@immutable
final class ForumNativeSurfaceShadows {
  const ForumNativeSurfaceShadows._();

  static const double cardAlpha = 0.05;
  static const double cardBlurRadius = 7;
  static const Offset cardOffset = Offset(0, 2);

  static List<BoxShadow> card(Color stateLayer) {
    return <BoxShadow>[
      BoxShadow(
        color: stateLayer.withValues(alpha: cardAlpha),
        blurRadius: cardBlurRadius,
        offset: cardOffset,
      ),
    ];
  }
}
