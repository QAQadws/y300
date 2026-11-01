import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';

import '../models/novel_reader_native_prepared_chapter.dart';
import 'novel_reader_background_work.dart';
import 'novel_reader_native_render_environment.dart';
import 'novel_reader_pagination_cancellation.dart';

enum NovelReaderNativeLayoutInputFailure {
  geometry,
  opaquePaint,
  scaling,
  budget,
}

final class NovelReaderNativeLayoutInputException implements Exception {
  const NovelReaderNativeLayoutInputException(this.failure);
  final NovelReaderNativeLayoutInputFailure failure;
  @override
  String toString() => 'NovelReaderNativeLayoutInputException(${failure.name})';
}

/// Exact, frozen native inputs and their stable fingerprint. The fingerprint
/// and session cannot accidentally use different font/scaler/box snapshots.
/// No Context, native layout, cache or reading authority is retained here.
final class NovelReaderNativeLayoutScope {
  const NovelReaderNativeLayoutScope._({
    required this.chapter,
    required this.reader,
    required this.textScaler,
    required this.backgroundColor,
    required this.width,
    required this.height,
    required this.paginationKey,
    required this.maxNativeHandlesPerPage,
  });
  static const fingerprintRevision = 6;
  final NovelReaderNativePreparedChapter chapter;
  final ForumBodyReaderStyle reader;
  final TextScaler textScaler;
  final Color backgroundColor;
  final double width;
  final double height;
  final String paginationKey;
  final int maxNativeHandlesPerPage;

  static Future<NovelReaderNativeLayoutScope> prepare({
    required NovelReaderNativePreparedChapter chapter,
    required NovelReaderNativeRenderEnvironment environment,
    required double width,
    required double height,
    required NovelReaderPaginationCancellationToken cancellation,
    int maxScaledFontSizes = 2048,
    int fontCollectionGeneration = 0,
    int maxIssuedLeases = 512,
  }) async {
    cancellation.throwIfCancelled();
    final pageHandleLimit = _pageHandleLimit(maxIssuedLeases);
    if (!width.isFinite ||
        width <= 0 ||
        width > 16384 ||
        !height.isFinite ||
        height <= 0 ||
        height > 16384) {
      throw const NovelReaderNativeLayoutInputException(
        NovelReaderNativeLayoutInputFailure.geometry,
      );
    }
    if (maxScaledFontSizes <= 0) throw ArgumentError.value(maxScaledFontSizes);
    if (fontCollectionGeneration < 0) {
      throw ArgumentError.value(fontCollectionGeneration);
    }
    final original = environment.reader;
    final reader = ForumBodyReaderStyle(
      textStyle: _freezeStyle(original.textStyle),
      fontRevision: original.fontRevision,
      linkColor: _freezeColor(original.linkColor)!,
      textAlign: original.textAlign,
      textDirection: original.textDirection,
      paragraphBefore: original.paragraphBefore,
      paragraphAfter: original.paragraphAfter,
      firstLineIndent: original.firstLineIndent,
      policy: ForumBodyStylePolicy(original.policy.values),
    );
    final document = chapter.document;
    final sizes = await cancellation.waitFor(
      NovelReaderBackgroundWork.run(
        // Style traversal cost follows nodes, not the length of one text node.
        codeUnits: document.parsedNodeCount * 24,
        transform: () => _fontSizes(document, reader, maxScaledFontSizes),
      ),
    );
    cancellation.throwIfCancelled();
    final scales = <double, double>{};
    for (final size in sizes) {
      final scaled = environment.textScaler.scale(size);
      // A custom scaler is caller code and can retire the request reentrantly.
      cancellation.throwIfCancelled();
      if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
        throw const NovelReaderNativeLayoutInputException(
          NovelReaderNativeLayoutInputFailure.scaling,
        );
      }
      scales[size] = scaled;
    }
    final background = _freezeColor(environment.backgroundColor)!;
    final payload = <Object?>[
      fingerprintRevision,
      chapter.episodeId,
      document.identity.cacheIdentity,
      ForumBodyStyleResolver.revision,
      ForumBodyTextFlowCursor.revision,
      ForumBodyBlockFlowCursor.revision,
      ForumBodyParagraphLayout.backendRevision,
      ForumBodyTextPageComposer.revision,
      ForumBodyTextPageSession.inlinePlanRevision,
      ForumBodyInlineSpanContent.revision,
      ForumBodyInlineParagraphLayout.revision,
      ForumBodyRubyContentCursor.revision,
      ForumBodyRubyGroupLayout.revision,
      ForumBodyRubySegmentMetrics.revision,
      ForumBodyRubySoftSpaceMetrics.revision,
      ForumBodyTextBandContent.revision,
      ForumBodyTextBandLayout.revision,
      HtmlDisplayTextProjection.revision,
      HtmlInlineTextProjection.revision,
      HtmlTextBandProjection.revision,
      NovelReaderSourceProvenance.revision,
      width,
      height,
      pageHandleLimit,
      reader.fontRevision,
      fontCollectionGeneration,
      _styleValue(reader.textStyle),
      _colorValue(reader.linkColor),
      _colorValue(background),
      reader.textAlign.name,
      reader.textDirection.name,
      reader.paragraphBefore,
      reader.paragraphAfter,
      reader.firstLineIndent.value,
      reader.firstLineIndent.unit.name,
      for (final property in ForumBodyStyleProperty.values)
        (reader.policy.values[property] ?? ForumBodyStyleScope.asDefault).name,
      for (final entry in scales.entries) [entry.key, entry.value],
    ];
    return NovelReaderNativeLayoutScope._(
      chapter: chapter,
      reader: reader,
      textScaler: _CapturedTextScaler(scales, reader.textStyle.fontSize!),
      backgroundColor: background,
      width: width,
      height: height,
      maxNativeHandlesPerPage: pageHandleLimit,
      paginationKey:
          'native-$fingerprintRevision-${sha256.convert(utf8.encode(jsonEncode(payload)))}',
    );
  }

  ForumBodyTextPageSession openSession({
    required ForumBodyParagraphCache cache,
    required String layoutId,
    required ForumBodyTextPageSessionLimits limits,
  }) {
    if (_pageHandleLimit(limits.maxIssuedLeases) != maxNativeHandlesPerPage) {
      throw ArgumentError(
        'Session handle budget differs from its layout fingerprint',
      );
    }
    return ForumBodyTextPageSession(
      document: chapter.document,
      reader: reader,
      textScaler: textScaler,
      width: width,
      height: height,
      cache: cache,
      layoutId: layoutId,
      limits: limits,
      // Current and target pages coexist during a real PageView turn. Reserve
      // their shared issued-handle budget before publishing legal physical rows.
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      // A mixed run retains text parts, annotation containers and groups in
      // addition to its glyph runs. Budget these pure values separately; native
      // cache and issued-handle admission remain under their existing limits.
      rubyLimits: const ForumBodyRubyContentLimits(maxStructureItems: 2048),
    );
  }
}

int _pageHandleLimit(int issued) {
  if (issued <= 0) throw ArgumentError.value(issued, 'maxIssuedLeases');
  return issued >= 2 ? issued ~/ 2 : 1;
}

List<double> _fontSizes(
  ForumBodyDocument document,
  ForumBodyReaderStyle reader,
  int limit,
) {
  final cursor = const ForumBodyStyleResolver().open(document, reader);
  final sizes = <double>{cursor.root.textStyle.fontSize!};
  try {
    while (cursor.moveNext()) {
      sizes.add(cursor.currentStyle!.textStyle.fontSize!);
      if (sizes.length > limit) {
        throw const NovelReaderNativeLayoutInputException(
          NovelReaderNativeLayoutInputFailure.budget,
        );
      }
    }
    return List.unmodifiable(sizes.toList()..sort());
  } finally {
    cursor.close();
  }
}

final class _CapturedTextScaler extends TextScaler {
  _CapturedTextScaler(Map<double, double> sizes, this.rootSize)
    : sizes = Map.unmodifiable(sizes);
  final Map<double, double> sizes;
  final double rootSize;
  @override
  double scale(double fontSize) =>
      sizes[fontSize] ??
      (throw const NovelReaderNativeLayoutInputException(
        NovelReaderNativeLayoutInputFailure.scaling,
      ));
  @override
  double get textScaleFactor => scale(rootSize) / rootSize;
}

Color? _freezeColor(Color? color) => color == null
    ? null
    : Color.from(
        alpha: color.a,
        red: color.r,
        green: color.g,
        blue: color.b,
        colorSpace: color.colorSpace,
      );

TextStyle _freezeStyle(TextStyle style) {
  // Paint may hold mutable shaders/filters that have no stable value encoding.
  // Reject them rather than claiming two native paint inputs are equivalent.
  if (style.foreground != null || style.background != null) {
    throw const NovelReaderNativeLayoutInputException(
      NovelReaderNativeLayoutInputFailure.opaquePaint,
    );
  }
  return TextStyle(
    inherit: false,
    color: _freezeColor(style.color),
    backgroundColor: _freezeColor(style.backgroundColor),
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback == null
        ? null
        : List.unmodifiable(style.fontFamilyFallback!),
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    textBaseline: style.textBaseline,
    height: style.height,
    leadingDistribution: style.leadingDistribution,
    locale: style.locale,
    decoration: style.decoration,
    decorationColor: _freezeColor(style.decorationColor),
    decorationStyle: style.decorationStyle,
    decorationThickness: style.decorationThickness,
    shadows: style.shadows == null
        ? null
        : List.unmodifiable([
            for (final shadow in style.shadows!)
              Shadow(
                color: _freezeColor(shadow.color)!,
                offset: shadow.offset,
                blurRadius: shadow.blurRadius,
              ),
          ]),
    fontFeatures: style.fontFeatures == null
        ? null
        : List.unmodifiable(style.fontFeatures!),
    fontVariations: style.fontVariations == null
        ? null
        : List.unmodifiable(style.fontVariations!),
    overflow: style.overflow,
  );
}

Object? _colorValue(Color? color) => color == null
    ? null
    : [color.a, color.r, color.g, color.b, color.colorSpace.name];

List<Object?> _styleValue(TextStyle style) => [
  style.inherit,
  _colorValue(style.color),
  _colorValue(style.backgroundColor),
  style.fontFamily,
  style.fontFamilyFallback,
  style.fontSize,
  style.fontWeight?.value,
  style.fontStyle?.name,
  style.letterSpacing,
  style.wordSpacing,
  style.textBaseline?.name,
  style.height,
  style.leadingDistribution?.name,
  style.locale?.languageCode,
  style.locale?.scriptCode,
  style.locale?.countryCode,
  style.decoration == null
      ? null
      : [
          style.decoration!.contains(TextDecoration.underline),
          style.decoration!.contains(TextDecoration.overline),
          style.decoration!.contains(TextDecoration.lineThrough),
        ],
  _colorValue(style.decorationColor),
  style.decorationStyle?.name,
  style.decorationThickness,
  style.shadows
      ?.map(
        (shadow) => [
          _colorValue(shadow.color),
          shadow.offset.dx,
          shadow.offset.dy,
          shadow.blurRadius,
        ],
      )
      .toList(),
  style.fontFeatures
      ?.map((feature) => [feature.feature, feature.value])
      .toList(),
  style.fontVariations
      ?.map((variation) => [variation.axis, variation.value])
      .toList(),
  style.overflow?.name,
];
