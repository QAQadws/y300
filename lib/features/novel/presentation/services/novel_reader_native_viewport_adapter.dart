import 'dart:math' as math;
import 'dart:ui' show TextDirection;

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

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

/// Freeze the screen and its columns together after safe area and margins.
/// The default single-column cap applies per column on wide displays. An
/// explicitly requested width always caps the whole screen.
({double width, ForumBodyPageColumns columns}) resolveNovelReaderNativePageBox(
  NovelReaderPreferences preferences, {
  required double availableWidth,
  required double? maximumWidth,
  required double scaledBodyFontSize,
}) {
  const gap = 24.0;
  final count = preferences.viewport.columns?.count ?? 1;
  final singleWidth = math.min(availableWidth, maximumWidth ?? availableWidth);
  if (count > 1 && preferences.flowMode != NovelReaderFlowMode.vertical) {
    final cap =
        maximumWidth != null && preferences.viewport.contentWidth == null
        ? maximumWidth * count + gap * (count - 1)
        : maximumWidth;
    final width = math.min(availableWidth, cap ?? availableWidth);
    final columns = ForumBodyPageColumns(
      count: count,
      gap: gap,
      readingOrder: preferences.flowMode == NovelReaderFlowMode.pagedRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
    );
    if (columns.widthFor(width) >= math.max(260, scaledBodyFontSize * 12)) {
      return (width: width, columns: columns);
    }
  }
  return (width: singleWidth, columns: const ForumBodyPageColumns());
}
