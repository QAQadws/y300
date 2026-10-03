import 'package:flutter/foundation.dart';

enum ThreadPostResourceLayoutHintSource {
  htmlAttribute,
  cachedDimension,
  contentDefault,
}

@immutable
class ThreadPostBlockImageLayoutHint {
  const ThreadPostBlockImageLayoutHint({
    required this.aspectRatio,
    required this.source,
  });

  final double aspectRatio;
  final ThreadPostResourceLayoutHintSource source;

  @override
  bool operator ==(Object other) =>
      other is ThreadPostBlockImageLayoutHint &&
      aspectRatio == other.aspectRatio &&
      source == other.source;

  @override
  int get hashCode => Object.hash(aspectRatio, source);
}
