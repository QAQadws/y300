import 'dart:convert';

import 'package:flutter/material.dart';

/// One resolved reader layout shared by TextPainter, the probe and visible HTML.
final class NovelReaderPaginationRenderEnvironment {
  const NovelReaderPaginationRenderEnvironment._({
    required this.textStyle,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.mediaQuery,
    required this.theme,
    required this.linearScaleFactor,
    required bool softWrap,
    required TextOverflow overflow,
    required int? maxLines,
    required TextWidthBasis textWidthBasis,
    required TextHeightBehavior? textHeightBehavior,
  }) : _softWrap = softWrap,
       _overflow = overflow,
       _maxLines = maxLines,
       _textWidthBasis = textWidthBasis,
       _textHeightBehavior = textHeightBehavior;

  factory NovelReaderPaginationRenderEnvironment.capture(
    BuildContext context, {
    required TextStyle textStyle,
    required TextAlign textAlign,
  }) {
    final defaults = DefaultTextStyle.of(context);
    final media = MediaQuery.of(context);
    // fwfh 0.17.2 reads this compatibility factor, which can differ from a
    // nonlinear scaler's 14px sample. Preserve its existing rendering scale.
    // ignore: deprecated_member_use
    final factor = media.textScaler.textScaleFactor;
    final scaler = TextScaler.linear(factor);
    return NovelReaderPaginationRenderEnvironment._(
      textStyle: defaults.style.merge(textStyle).copyWith(inherit: false),
      textAlign: textAlign,
      textDirection: Directionality.of(context),
      textScaler: scaler,
      mediaQuery: media.copyWith(textScaler: scaler),
      theme: Theme.of(context),
      linearScaleFactor: factor,
      softWrap: defaults.softWrap,
      overflow: defaults.overflow,
      maxLines: defaults.maxLines,
      textWidthBasis: defaults.textWidthBasis,
      textHeightBehavior: defaults.textHeightBehavior,
    );
  }

  final TextStyle textStyle;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final MediaQueryData mediaQuery;
  final ThemeData theme;
  final double linearScaleFactor;
  final bool _softWrap;
  final TextOverflow _overflow;
  final int? _maxLines;
  final TextWidthBasis _textWidthBasis;
  final TextHeightBehavior? _textHeightBehavior;

  Object get sessionSignature => (
    textStyle,
    textAlign,
    textDirection,
    textScaler,
    mediaQuery,
    theme,
    _softWrap,
    _overflow,
    _maxLines,
    _textWidthBasis,
    _textHeightBehavior,
  );

  /// Stable layout values only, without object hashes or debug descriptions.
  String get layoutSignature => jsonEncode(<Object?>[
    textStyle.fontFamily,
    textStyle.fontFamilyFallback,
    textStyle.fontSize,
    textStyle.fontWeight?.value,
    textStyle.fontStyle?.name,
    textStyle.height,
    textStyle.leadingDistribution?.name,
    textStyle.letterSpacing,
    textStyle.wordSpacing,
    textStyle.textBaseline?.name,
    textStyle.locale?.toLanguageTag(),
    textStyle.fontFeatures
        ?.map((feature) => [feature.feature, feature.value])
        .toList(),
    textStyle.fontVariations
        ?.map((variation) => [variation.axis, variation.value])
        .toList(),
    textAlign.name,
    textDirection.name,
    linearScaleFactor,
    _softWrap,
    _overflow.name,
    _maxLines,
    _textWidthBasis.name,
    _textHeightBehavior?.applyHeightToFirstAscent,
    _textHeightBehavior?.applyHeightToLastDescent,
    _textHeightBehavior?.leadingDistribution.name,
  ]);

  Widget wrap(Widget child) => Theme(
    data: theme,
    child: MediaQuery(
      data: mediaQuery,
      child: Directionality(
        textDirection: textDirection,
        child: DefaultTextStyle(
          style: textStyle,
          textAlign: textAlign,
          softWrap: _softWrap,
          overflow: _overflow,
          maxLines: _maxLines,
          textWidthBasis: _textWidthBasis,
          textHeightBehavior: _textHeightBehavior,
          child: child,
        ),
      ),
    ),
  );
}
