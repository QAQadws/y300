import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

/// Maps novel preferences onto the shared text-conversion direction.
extension NovelReaderPreferencesSharedBridge on NovelReaderPreferences {
  /// Shared text-conversion direction mapped from the novel preference enum.
  TextConversionMode get sharedConversionMode {
    switch (conversionMode) {
      case NovelReaderConversionMode.none:
        return TextConversionMode.none;
      case NovelReaderConversionMode.toSimplified:
        return TextConversionMode.toSimplified;
      case NovelReaderConversionMode.toTraditional:
        return TextConversionMode.toTraditional;
    }
  }
}
