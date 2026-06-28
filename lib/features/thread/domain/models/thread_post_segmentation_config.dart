import 'package:flutter/foundation.dart';

/// Single source of truth for post body segmentation thresholds.
///
/// 600-char rationale: above this, a single ListView item causes noticeable
/// per-frame layout overhead; splitting keeps virtualisation effective
/// without over-fragmenting content.
@immutable
class ThreadPostSegmentationConfig {
  const ThreadPostSegmentationConfig({this.maxSegmentTextLength = 600})
    : assert(maxSegmentTextLength > 0);

  static const ThreadPostSegmentationConfig standard =
      ThreadPostSegmentationConfig();

  final int maxSegmentTextLength;

  @override
  bool operator ==(Object other) =>
      other is ThreadPostSegmentationConfig &&
      other.maxSegmentTextLength == maxSegmentTextLength;

  @override
  int get hashCode => maxSegmentTextLength.hashCode;
}
