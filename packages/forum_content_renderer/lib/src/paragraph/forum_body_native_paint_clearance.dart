import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Shared conservative native font/decoration/shadow envelope, not ink bounds.
/// Callers retire the preparation on rejection; partially accumulated inputs
/// must never authorize a drawing. No scaler, source or native handle is held.
final class ForumBodyNativePaintClearance {
  ForumBodyNativePaintClearance(this.fontClearance) {
    if (!fontClearance.isFinite || fontClearance < 0) {
      throw ArgumentError.value(fontClearance);
    }
  }
  final double fontClearance;
  double _decoration = 0, _shadowTop = 0, _shadowBottom = 0, _horizontal = 0;
  double get top => _decoration + _shadowTop;
  double get bottom => _decoration + _shadowBottom;

  bool include(TextStyle text) {
    final thickness = text.decorationThickness ?? 1;
    if (!thickness.isFinite || thickness < 0) return false;
    _decoration = math.max(_decoration, fontClearance * math.max(1, thickness));
    for (final paint in [text.foreground, text.background]) {
      if (paint != null &&
          (paint.style != PaintingStyle.fill ||
              paint.maskFilter != null ||
              paint.imageFilter != null)) {
        return false;
      }
    }
    for (final shadow in text.shadows ?? const <Shadow>[]) {
      final reach = 3 * shadow.blurSigma + 1;
      final upper = reach - shadow.offset.dy, lower = reach + shadow.offset.dy;
      if (!upper.isFinite ||
          !lower.isFinite ||
          reach + shadow.offset.dx.abs() + _decoration > 16384 ||
          shadow.offset.dy.abs() > 16384) {
        return false;
      }
      _shadowTop = math.max(_shadowTop, upper);
      _shadowBottom = math.max(_shadowBottom, lower);
      _horizontal = math.max(_horizontal, reach + shadow.offset.dx.abs());
    }
    return true;
  }

  Rect? envelope(Rect bounds) {
    if (_decoration + _horizontal > 16384) return null;
    return Rect.fromLTRB(
      bounds.left - _decoration,
      bounds.top - top,
      bounds.right + _decoration,
      bounds.bottom + bottom,
    );
  }
}
