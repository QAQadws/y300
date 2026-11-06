import 'package:flutter/foundation.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// A borrowed layout for reading published text and observing its retirement.
typedef NovelReaderLogicalSelectionSource = ({
  ForumBodyTextPageSession session,
  VoidCallback Function(VoidCallback) onRetired,
});
