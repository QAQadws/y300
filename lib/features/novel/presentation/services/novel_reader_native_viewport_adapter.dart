import 'dart:math' as math;

import '../../domain/models/novel_reader_preferences.dart';

/// One projection for the outer Widget frame; its actual constrained body box
/// is still passed directly to the native host for measurement and delivery.
({double left, double top, double right, double bottom, double? maximumWidth})
resolveNovelReaderNativeViewport(NovelReaderPreferences preferences) {
  final request = preferences.viewport;
  if (!request.isValid) throw ArgumentError('Invalid reader viewport');
  final legacyPadding = preferences.pagePadding.clamp(0.0, 96.0).toDouble();
  final width = request.contentWidth;
  return (
    left: request.left ?? legacyPadding,
    top: request.top ?? legacyPadding,
    right: request.right ?? legacyPadding,
    bottom: request.bottom ?? legacyPadding,
    maximumWidth: width == null
        ? math.max(160.0, preferences.contentMaxWidth)
        : width.mode == NovelReaderContentWidthMode.available
        ? null
        : width.logicalPixels,
  );
}
