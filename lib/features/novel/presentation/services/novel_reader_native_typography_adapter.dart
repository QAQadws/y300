import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_preferences.dart';

({ForumBodyLength indent, ForumBodyStylePolicy policy})
resolveNovelReaderNativeIndent(
  NovelReaderPreferences preferences,
  ForumBodyStylePolicy? base,
) {
  final request = preferences.typography.firstLineIndent;
  if (request != null && !request.isValid) {
    throw ArgumentError('Invalid reader indentation');
  }
  final effective = preferences.effectiveFirstLineIndent;
  return (
    indent: ForumBodyLength(
      effective.value,
      effective.unit == NovelReaderIndentUnit.em
          ? ForumBodyLengthUnit.em
          : ForumBodyLengthUnit.px,
    ),
    policy: request == null
        ? (base ?? ForumBodyStylePolicy())
        : ForumBodyStylePolicy({
            ...?base?.values,
            ForumBodyStyleProperty.textIndent: switch (request.scope) {
              NovelReaderStyleScope.asDefault => ForumBodyStyleScope.asDefault,
              NovelReaderStyleScope.forceBody => ForumBodyStyleScope.forceBody,
              NovelReaderStyleScope.forceAll => ForumBodyStyleScope.forceAll,
            },
          }),
  );
}
