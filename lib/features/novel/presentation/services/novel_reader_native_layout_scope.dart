import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';

import '../models/novel_reader_native_prepared_chapter.dart';
import 'novel_reader_background_work.dart';
import 'novel_reader_native_render_environment.dart';
import 'novel_reader_native_image_resources.dart';
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
    required this.columns,
    required this.paginationKey,
    required this.maxNativeHandlesPerPage,
    required this.maxNativeEntriesPerPage,
    required this.maxNativeEstimatedBytesPerPage,
    required this.images,
    required this.collapses,
    required int fontCollectionGeneration,
    required String paragraphInputs,
    required bool usesQuoteTheme,
    required bool avoidIsolatedLines,
    required bool keepHeadingWithNext,
  }) : _fontCollectionGeneration = fontCollectionGeneration,
       _paragraphInputs = paragraphInputs,
       _usesQuoteTheme = usesQuoteTheme,
       _avoidIsolatedLines = avoidIsolatedLines,
       _keepHeadingWithNext = keepHeadingWithNext;
  static const fingerprintRevision = 16;
  final NovelReaderNativePreparedChapter chapter;
  final ForumBodyReaderStyle reader;
  final TextScaler textScaler;

  /// Canvas paint only; native text and inline backgrounds stay in the key.
  final Color backgroundColor;
  final double width;
  final double height;
  final ForumBodyPageColumns columns;
  final String paginationKey;
  final int maxNativeHandlesPerPage;
  final int? maxNativeEntriesPerPage;
  final int? maxNativeEstimatedBytesPerPage;
  final NovelReaderNativeImageCatalog? images;
  final ForumBodyCollapseLayout? collapses;
  final int _fontCollectionGeneration;
  final String _paragraphInputs;
  final bool _usesQuoteTheme;
  final bool _avoidIsolatedLines;
  final bool _keepHeadingWithNext;

  static Future<NovelReaderNativeLayoutScope> prepare({
    required NovelReaderNativePreparedChapter chapter,
    required NovelReaderNativeRenderEnvironment environment,
    required double width,
    required double height,
    ForumBodyPageColumns columns = const ForumBodyPageColumns(),
    required NovelReaderPaginationCancellationToken cancellation,
    int maxScaledFontSizes = 2048,
    int fontCollectionGeneration = 0,
    int maxIssuedLeases = 512,
    int? maxParagraphCacheEntries,
    int? maxParagraphCacheEstimatedBytes,
    NovelReaderNativeImageCatalog? images,
    ForumBodyCollapseLayout? collapses,
  }) async {
    cancellation.throwIfCancelled();
    if (images != null && images.identity != chapter.identity) {
      throw StateError('Native image geometry source changed');
    }
    if (collapses != null && !identical(collapses.document, chapter.document)) {
      throw ArgumentError('Native collapse layout source changed');
    }
    final pageHandleLimit = _pageHandleLimit(maxIssuedLeases);
    if (maxParagraphCacheEntries != null && maxParagraphCacheEntries <= 0) {
      throw ArgumentError.value(
        maxParagraphCacheEntries,
        'maxParagraphCacheEntries',
      );
    }
    // Current and target must coexist. Keep two native slots for temporary
    // source metrics; glyph bands deduplicate independently of logical handles.
    final pageEntryLimit = maxParagraphCacheEntries == null
        ? null
        : maxParagraphCacheEntries > 3
        ? (maxParagraphCacheEntries - 2) ~/ 2
        : 1;
    if (maxParagraphCacheEstimatedBytes != null &&
        maxParagraphCacheEstimatedBytes <= 0) {
      throw ArgumentError.value(
        maxParagraphCacheEstimatedBytes,
        'maxParagraphCacheEstimatedBytes',
      );
    }
    const fontReserve =
        2 * ForumBodyParagraphCache.sourceFreeFontEstimatedBytes;
    // The current and target pages share the original owner budget. Keep
    // source-free font measurements outside both page estimates; actual paint
    // growth still goes through the cache's existing aggregate admission.
    final pageByteLimit = maxParagraphCacheEstimatedBytes == null
        ? null
        : maxParagraphCacheEstimatedBytes > fontReserve + 1
        ? (maxParagraphCacheEstimatedBytes - fontReserve) ~/ 2
        : maxParagraphCacheEstimatedBytes > 1
        ? maxParagraphCacheEstimatedBytes ~/ 2
        : 1;
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
    final reader = _freezeReader(environment.reader);
    final document = chapter.document;
    final inputs = await cancellation.waitFor(
      NovelReaderBackgroundWork.run(
        // Style traversal cost follows nodes, not the length of one text node.
        codeUnits: document.parsedNodeCount * 24,
        transform: () => _fontInputs(document, reader, maxScaledFontSizes),
      ),
    );
    cancellation.throwIfCancelled();
    final scales = <double, double>{};
    for (final size in inputs.sizes) {
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
    final revisions = _nativeRevisions();
    final readerValues = _readerValues(
      reader,
      fontCollectionGeneration,
      usesQuoteTheme: inputs.usesQuoteTheme,
    );
    final payload = <Object?>[
      ...revisions,
      chapter.episodeId,
      document.identity.cacheIdentity,
      width,
      height,
      if (columns.count > 1)
        [columns.count, columns.gap, columns.readingOrder.name],
      pageHandleLimit,
      pageEntryLimit,
      pageByteLimit,
      environment.avoidIsolatedLines,
      environment.keepHeadingWithNext,
      images?.geometryIdentity,
      if (collapses != null)
        [
          for (final fold in collapses.sections.values)
            if (fold.expanded != fold.initiallyExpanded)
              [fold.id, fold.expanded],
        ],
      ...readerValues,
      // The canvas is painted outside native paragraphs. Text/inline colors
      // above remain part of this signature and still replace painted inputs.
      for (final entry in scales.entries) [entry.key, entry.value],
    ];
    return NovelReaderNativeLayoutScope._(
      chapter: chapter,
      reader: reader,
      textScaler: _CapturedTextScaler(scales, reader.textStyle.fontSize!),
      backgroundColor: background,
      width: width,
      height: height,
      columns: columns,
      maxNativeHandlesPerPage: pageHandleLimit,
      maxNativeEntriesPerPage: pageEntryLimit,
      maxNativeEstimatedBytesPerPage: pageByteLimit,
      images: images,
      collapses: collapses,
      fontCollectionGeneration: fontCollectionGeneration,
      paragraphInputs: jsonEncode([...revisions, ...readerValues]),
      usesQuoteTheme: inputs.usesQuoteTheme,
      avoidIsolatedLines: environment.avoidIsolatedLines,
      keepHeadingWithNext: environment.keepHeadingWithNext,
      paginationKey:
          'native-$fingerprintRevision-${sha256.convert(utf8.encode(jsonEncode(payload)))}',
    );
  }

  /// Recheck existing immutable inputs without a document/style traversal.
  /// The caller must still own this chapter/box; no callback is retained.
  /// Custom scalers are caller code, so retirement is checked on each sample.
  NovelReaderNativeLayoutScope? tryUpdateCanvas({
    required NovelReaderNativeRenderEnvironment environment,
    required double width,
    required double height,
    ForumBodyPageColumns columns = const ForumBodyPageColumns(),
    required int fontCollectionGeneration,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent() ||
        width != this.width ||
        height != this.height ||
        columns != this.columns ||
        environment.avoidIsolatedLines != _avoidIsolatedLines ||
        environment.keepHeadingWithNext != _keepHeadingWithNext ||
        fontCollectionGeneration != _fontCollectionGeneration) {
      return null;
    }
    final candidate = _freezeReader(environment.reader);
    if (!isCurrent() ||
        jsonEncode([
              ..._nativeRevisions(),
              ..._readerValues(
                candidate,
                fontCollectionGeneration,
                usesQuoteTheme: _usesQuoteTheme,
              ),
            ]) !=
            _paragraphInputs) {
      return null;
    }
    for (final entry in (textScaler as _CapturedTextScaler).sizes.entries) {
      if (!isCurrent()) return null;
      final scaled = environment.textScaler.scale(entry.key);
      if (!isCurrent() || scaled != entry.value) return null;
    }
    final background = _freezeColor(environment.backgroundColor)!;
    if (!isCurrent()) return null;
    return NovelReaderNativeLayoutScope._(
      chapter: chapter,
      reader: reader,
      textScaler: textScaler,
      backgroundColor: background,
      width: width,
      height: height,
      columns: columns,
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      maxNativeEntriesPerPage: maxNativeEntriesPerPage,
      maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
      images: images,
      collapses: collapses,
      fontCollectionGeneration: fontCollectionGeneration,
      paragraphInputs: _paragraphInputs,
      usesQuoteTheme: _usesQuoteTheme,
      avoidIsolatedLines: _avoidIsolatedLines,
      keepHeadingWithNext: _keepHeadingWithNext,
      paginationKey: paginationKey,
    );
  }

  ForumBodyTextPageSession openSession({
    required ForumBodyParagraphCache cache,
    required String layoutId,
    required ForumBodyTextPageSessionLimits limits,
    ForumBodyTableExtent tableExtent = ForumBodyTableExtent.bookPage,
  }) {
    if (_pageHandleLimit(limits.maxIssuedLeases) != maxNativeHandlesPerPage) {
      throw ArgumentError(
        'Session handle budget differs from its layout fingerprint',
      );
    }
    final catalog = images;
    return ForumBodyTextPageSession(
      document: chapter.document,
      reader: reader,
      textScaler: textScaler,
      width: width,
      height: height,
      columns: columns,
      cache: cache,
      layoutId: layoutId,
      limits: limits,
      collapses: collapses,
      dedicatedTables: true,
      captureFloats: true,
      tableExtent: tableExtent,
      avoidIsolatedLines: _avoidIsolatedLines,
      keepHeadingWithNext: _keepHeadingWithNext,
      imageResolver: catalog?.resolve,
      inlineImageResolver: catalog == null
          ? null
          : (identity, element, style) => catalog.resolveInline(
              identity,
              element,
              style,
              textScaler,
              height,
            ),
      // Current and target pages coexist during a real PageView turn. Reserve
      // their shared issued-handle budget before publishing legal physical rows.
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      maxNativeEntriesPerPage: maxNativeEntriesPerPage,
      maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
      // A mixed run retains text parts, annotation containers and groups in
      // addition to its glyph runs. Budget these pure values separately; native
      // cache and issued-handle admission remain under their existing limits.
      rubyLimits: const ForumBodyRubyContentLimits(maxStructureItems: 2048),
    );
  }
}

ForumBodyReaderStyle _freezeReader(ForumBodyReaderStyle original) =>
    ForumBodyReaderStyle(
      textStyle: _freezeStyle(original.textStyle),
      fontRevision: original.fontRevision,
      linkColor: _freezeColor(original.linkColor)!,
      textAlign: original.textAlign,
      textDirection: original.textDirection,
      paragraphBefore: original.paragraphBefore,
      paragraphAfter: original.paragraphAfter,
      firstLineIndent: original.firstLineIndent,
      compressBlankLines: original.compressBlankLines,
      removeSourceIndent: original.removeSourceIndent,
      roleFontScales: original.roleFontScales,
      rubyFontScale: original.rubyFontScale,
      showRubyAnnotations: original.showRubyAnnotations,
      policy: ForumBodyStylePolicy(original.policy.values),
      theme: _freezeTheme(original.theme),
    );

List<int> _nativeRevisions() => [
  NovelReaderNativeLayoutScope.fingerprintRevision,
  ForumBodyStyleResolver.revision,
  ForumBodyTextFlowCursor.revision,
  ForumBodyBlockFlowCursor.revision,
  ForumBodyParagraphLayout.backendRevision,
  ForumBodyTextPageComposer.revision,
  ForumBodyTextPageSession.inlinePlanRevision,
  ForumBodyTextPageSession.paragraphPlanRevision,
  ForumBodyTextPageSession.inlineFontFrameRevision,
  ForumBodyEmphasisParagraphMetrics.revision,
  ForumBodyEmphasisRowAllocation.revision,
  ForumBodyEmphasisLineMetrics.revision,
  ForumBodyEmphasisFragmentInput.revision,
  ForumBodyEmphasisFragmentLayout.revision,
  ForumBodyFittedEmphasisPlan.revision,
  ForumBodyTextPictureInput.revision,
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
];

/// Shared by the full fingerprint and the paint-only check. No native text
/// or policy input may bypass invalidation just because geometry looks equal.
List<Object?> _readerValues(
  ForumBodyReaderStyle reader,
  int fontGeneration, {
  required bool usesQuoteTheme,
}) => [
  reader.fontRevision,
  fontGeneration,
  _styleValue(reader.textStyle),
  _colorValue(reader.linkColor),
  if (usesQuoteTheme && reader.theme != null)
    [
      // Only semantic colors currently consumed by native content belong
      // here; the page canvas remains a separate paint-only input.
      _colorValue(reader.theme!.quoteSurface),
      _colorValue(reader.theme!.quoteForeground),
    ]
  else
    null,
  reader.textAlign.name,
  reader.textDirection.name,
  reader.paragraphBefore,
  reader.paragraphAfter,
  reader.firstLineIndent.value,
  reader.firstLineIndent.unit.name,
  reader.compressBlankLines,
  reader.removeSourceIndent,
  reader.roleFontScales.heading,
  reader.roleFontScales.quote,
  reader.roleFontScales.code,
  reader.rubyFontScale,
  reader.showRubyAnnotations,
  for (final property in ForumBodyStyleProperty.values)
    (reader.policy.values[property] ?? ForumBodyStyleScope.asDefault).name,
];

int _pageHandleLimit(int issued) {
  if (issued <= 0) throw ArgumentError.value(issued, 'maxIssuedLeases');
  return issued >= 2 ? issued ~/ 2 : 1;
}

({List<double> sizes, bool usesQuoteTheme}) _fontInputs(
  ForumBodyDocument document,
  ForumBodyReaderStyle reader,
  int limit,
) {
  final cursor = const ForumBodyStyleResolver().open(document, reader);
  final sizes = <double>{};
  var usesQuoteTheme = false;
  void include(ForumBodyResolvedStyle style) {
    usesQuoteTheme |= style.quoteDecoration != null;
    final size = style.textStyle.fontSize!;
    sizes.add(size);
    sizes.addAll(style.baselineShift.referenceFontSizes);
    // Marks use half the unscaled author size, then the platform's actual
    // per-size scale. Sampling only body sizes cannot freeze nonlinear marks.
    if (style.textEmphasis.isEnabled) sizes.add(size * .5);
    if (sizes.length > limit) {
      throw const NovelReaderNativeLayoutInputException(
        NovelReaderNativeLayoutInputFailure.budget,
      );
    }
  }

  try {
    include(cursor.root);
    while (cursor.moveNext()) {
      include(cursor.currentStyle!);
    }
    return (
      sizes: List<double>.unmodifiable(sizes.toList()..sort()),
      usesQuoteTheme: usesQuoteTheme,
    );
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

ForumHtmlThemeContext? _freezeTheme(ForumHtmlThemeContext? theme) =>
    theme == null
    ? null
    : ForumHtmlThemeContext(
        brightness: theme.brightness,
        surface: _freezeColor(theme.surface)!,
        foreground: _freezeColor(theme.foreground)!,
        link: _freezeColor(theme.link)!,
        quoteSurface: _freezeColor(theme.quoteSurface)!,
        quoteForeground: _freezeColor(theme.quoteForeground)!,
        codeSurface: _freezeColor(theme.codeSurface)!,
        codeForeground: _freezeColor(theme.codeForeground)!,
      );

Color? _freezeColor(Color? color) {
  if (color == null) return null;
  final alpha = color.a, red = color.r, green = color.g, blue = color.b;
  if (!alpha.isFinite || !red.isFinite || !green.isFinite || !blue.isFinite) {
    throw const NovelReaderNativeLayoutInputException(
      NovelReaderNativeLayoutInputFailure.opaquePaint,
    );
  }
  // Preserve finite extended-gamut components; do not quantize to ARGB32.
  return Color.from(
    alpha: alpha,
    red: red,
    green: green,
    blue: blue,
    colorSpace: color.colorSpace,
  );
}

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
