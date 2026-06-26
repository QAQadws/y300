import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

void main() {
  group('ForumNativeSurfaceShadows', () {
    test('card shadow matches forum display thread card elevation', () {
      const stateLayer = Color(0xFF531104);

      final shadow = ForumNativeSurfaceShadows.card(stateLayer).single;

      expect(ForumNativeSurfaceShadows.cardAlpha, 0.05);
      expect(ForumNativeSurfaceShadows.cardBlurRadius, 7);
      expect(ForumNativeSurfaceShadows.cardOffset, const Offset(0, 2));
      expect(shadow.color, stateLayer.withValues(alpha: 0.05));
      expect(shadow.blurRadius, 7);
      expect(shadow.offset, const Offset(0, 2));
    });
  });
}
