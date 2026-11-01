import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_preferences.dart';

({
  ForumBodyLength indent,
  double paragraphBefore,
  double paragraphAfter,
  ForumBodyStylePolicy policy,
})
resolveNovelReaderNativeTypography(
  NovelReaderPreferences preferences,
  ForumBodyStylePolicy? base,
) {
  final request = preferences.typography.firstLineIndent;
  if (request != null && !request.isValid) {
    throw ArgumentError('Invalid reader indentation');
  }
  final effective = preferences.effectiveFirstLineIndent;
  final spacing = preferences.typography.paragraphSpacing;
  if (spacing != null && !spacing.isValid) {
    throw ArgumentError('Invalid reader paragraph spacing');
  }
  final effectiveSpacing = preferences.effectiveParagraphSpacing;
  return (
    paragraphBefore: effectiveSpacing.before,
    paragraphAfter: effectiveSpacing.after,
    indent: ForumBodyLength(
      effective.value,
      effective.unit == NovelReaderIndentUnit.em
          ? ForumBodyLengthUnit.em
          : ForumBodyLengthUnit.px,
    ),
    policy: request == null && spacing == null
        ? (base ?? ForumBodyStylePolicy())
        : ForumBodyStylePolicy({
            ...?base?.values,
            if (request != null)
              ForumBodyStyleProperty.textIndent: _scope(request.scope),
            if (spacing != null)
              ForumBodyStyleProperty.paragraphSpacing: _scope(spacing.scope),
          }),
  );
}

ForumBodyStyleScope _scope(NovelReaderStyleScope value) => switch (value) {
  NovelReaderStyleScope.asDefault => ForumBodyStyleScope.asDefault,
  NovelReaderStyleScope.forceBody => ForumBodyStyleScope.forceBody,
  NovelReaderStyleScope.forceAll => ForumBodyStyleScope.forceAll,
};
