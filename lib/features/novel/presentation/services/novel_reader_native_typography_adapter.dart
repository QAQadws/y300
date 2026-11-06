import 'package:flutter/painting.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_preferences.dart';

({
  ForumBodyLength indent,
  double paragraphBefore,
  double paragraphAfter,
  double? letterSpacing,
  double? wordSpacing,
  ForumBodyRoleFontScales roleFontScales,
  FontWeight? fontWeight,
  TextAlign? textAlign,
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
  final letters = preferences.typography.letterSpacing;
  if (letters != null && !letters.isValid) {
    throw ArgumentError('Invalid reader letter spacing');
  }
  final words = preferences.typography.wordSpacing;
  if (words != null && !words.isValid) {
    throw ArgumentError('Invalid reader word spacing');
  }
  final sizeScope = preferences.typography.fontSizeScope;
  final roleSizes = preferences.typography.roleFontSizes;
  final forceAllSizes =
      sizeScope == NovelReaderStyleScope.forceAll ||
      (sizeScope == null &&
          base?.values[ForumBodyStyleProperty.fontSize] ==
              ForumBodyStyleScope.forceAll);
  double scale(int? percent) =>
      (NovelReaderRoleFontSizes.validPercent(percent) ??
          NovelReaderRoleFontSizes.defaultPercent) /
      100;
  final heightScope = preferences.typography.lineHeightScope;
  final weight = preferences.typography.fontWeight;
  final alignment = preferences.typography.textAlignment;
  final foregroundScope = preferences.colors.foregroundScope;
  final backgroundScope = preferences.colors.backgroundScope;
  return (
    textAlign: alignment == null
        ? null
        : switch (alignment.mode) {
            NovelReaderTextAlignMode.start => TextAlign.start,
            NovelReaderTextAlignMode.end => TextAlign.end,
            NovelReaderTextAlignMode.center => TextAlign.center,
            NovelReaderTextAlignMode.justify => TextAlign.justify,
          },
    fontWeight: resolveNovelReaderNativeFontWeight(weight),
    wordSpacing: words?.logicalPixels,
    roleFontScales: forceAllSizes
        ? ForumBodyReaderStyle.defaultRoleFontScales
        : (
            heading: scale(roleSizes.heading),
            quote: scale(roleSizes.quote),
            code: scale(roleSizes.code),
          ),
    letterSpacing: letters?.logicalPixels,
    paragraphBefore: effectiveSpacing.before,
    paragraphAfter: effectiveSpacing.after,
    indent: ForumBodyLength(
      effective.value,
      effective.unit == NovelReaderIndentUnit.em
          ? ForumBodyLengthUnit.em
          : ForumBodyLengthUnit.px,
    ),
    policy:
        request == null &&
            spacing == null &&
            letters == null &&
            words == null &&
            sizeScope == null &&
            heightScope == null &&
            weight == null &&
            alignment == null &&
            foregroundScope == null &&
            backgroundScope == null
        ? (base ?? ForumBodyStylePolicy())
        : ForumBodyStylePolicy({
            ...?base?.values,
            if (foregroundScope != null)
              ForumBodyStyleProperty.foreground: _scope(foregroundScope),
            if (backgroundScope != null)
              ForumBodyStyleProperty.background: _scope(backgroundScope),
            if (alignment != null)
              ForumBodyStyleProperty.textAlign: _scope(alignment.scope),
            if (weight != null)
              ForumBodyStyleProperty.fontWeight: _scope(weight.scope),
            if (sizeScope != null)
              ForumBodyStyleProperty.fontSize: _scope(sizeScope),
            if (heightScope != null)
              ForumBodyStyleProperty.lineHeight: _scope(heightScope),
            if (request != null)
              ForumBodyStyleProperty.textIndent: _scope(request.scope),
            if (spacing != null)
              ForumBodyStyleProperty.paragraphSpacing: _scope(spacing.scope),
            if (letters != null)
              ForumBodyStyleProperty.letterSpacing: _scope(letters.scope),
            if (words != null)
              ForumBodyStyleProperty.wordSpacing: _scope(words.scope),
          }),
  );
}

/// Shared by the native environment and font picker preview. This is a request
/// to the engine, not an assertion that a particular face or synthesis exists.
FontWeight? resolveNovelReaderNativeFontWeight(NovelReaderFontWeight? request) {
  if (request == null) return null;
  if (!request.isValid) throw ArgumentError('Invalid reader font weight');
  return FontWeight.values[request.value ~/ 100 - 1];
}

ForumBodyStyleScope _scope(NovelReaderStyleScope value) => switch (value) {
  NovelReaderStyleScope.asDefault => ForumBodyStyleScope.asDefault,
  NovelReaderStyleScope.forceBody => ForumBodyStyleScope.forceBody,
  NovelReaderStyleScope.forceAll => ForumBodyStyleScope.forceAll,
};
