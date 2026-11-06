import 'package:flutter/painting.dart';

/// Effective sizes captured for one layout. A successful lookup only reads
/// copied values, so the renderer can reuse validation for the same snapshot.
final class ForumBodyTextScaleSnapshot extends TextScaler {
  ForumBodyTextScaleSnapshot(
    Map<double, double> sizes, {
    required double rootSize,
    required Exception missingSize,
  }) : sizes = Map.unmodifiable(sizes),
       _rootSize = rootSize,
       _missingSize = missingSize;

  final Map<double, double> sizes;
  final double _rootSize;
  final Exception _missingSize;

  @override
  double scale(double fontSize) => sizes[fontSize] ?? (throw _missingSize);

  @override
  double get textScaleFactor => scale(_rootSize) / _rootSize;
}
