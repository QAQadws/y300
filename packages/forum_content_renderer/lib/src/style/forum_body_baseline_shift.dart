import 'package:flutter/painting.dart';

enum ForumBodyBaselineAlignment { baseline, subscript, superscript }

/// Retains each ancestor's own reference size until the actual TextScaler is
/// known. CSS vertical-align itself is not inherited; its placed box is.
final class ForumBodyBaselineShift {
  const ForumBodyBaselineShift.none()
    : parent = null,
      referenceFontSize = 0,
      factor = 0,
      depth = 0;
  const ForumBodyBaselineShift._(
    this.parent,
    this.referenceFontSize,
    this.factor,
    this.depth,
  );
  final ForumBodyBaselineShift? parent;
  final double referenceFontSize, factor;
  final int depth;
  bool get isEmpty => depth == 0;

  ForumBodyBaselineShift append(
    ForumBodyBaselineAlignment alignment,
    double size,
  ) {
    if (alignment == ForumBodyBaselineAlignment.baseline) return this;
    if (!size.isFinite || size <= 0 || depth >= 128) {
      throw ArgumentError('Invalid baseline reference font');
    }
    return ForumBodyBaselineShift._(
      this,
      size,
      alignment == ForumBodyBaselineAlignment.superscript ? .4 : -.2,
      depth + 1,
    );
  }

  Iterable<double> get referenceFontSizes sync* {
    for (var value = this; !value.isEmpty; value = value.parent!) {
      yield value.referenceFontSize;
    }
  }

  double resolve(TextScaler scaler, {void Function()? ensureCurrent}) {
    ensureCurrent?.call();
    final steps = <ForumBodyBaselineShift>[];
    for (var value = this; !value.isEmpty; value = value.parent!) {
      steps.add(value);
    }
    final scales = <double, double>{};
    var shift = 0.0;
    for (final step in steps.reversed) {
      final size = scales.putIfAbsent(
        step.referenceFontSize,
        () => scaler.scale(step.referenceFontSize),
      );
      ensureCurrent?.call();
      if (!size.isFinite || size <= 0 || size > 4096) {
        throw ArgumentError('Invalid scaled baseline reference font');
      }
      shift += size * step.factor;
    }
    if (!shift.isFinite || shift.abs() > 16384) {
      throw ArgumentError('Baseline shift exceeds layout bounds');
    }
    return shift;
  }
}
