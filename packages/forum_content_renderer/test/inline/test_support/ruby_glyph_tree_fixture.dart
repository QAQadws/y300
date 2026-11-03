import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyRubyTreeEmphasisPlacement rubyTreeEmphasisPlacementFixture(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final metrics = rubyTreeEmphasisMetricsFixture(
    html,
    cache,
    direction: direction,
    scaler: scaler,
  );
  final bands = ForumBodyRubyTreeDecorationBandsPreparation(
    input: metrics,
    ensureOwner: () {},
  );
  late ForumBodyRubyTreeDecorationBands decoration;
  try {
    while (!bands.isReady) {
      bands.advance(maxParts: 1);
    }
    decoration = bands.takeBands();
  } finally {
    bands.close();
  }
  final placement = ForumBodyRubyTreeEmphasisPlacementPreparation(
    input: decoration,
    ensureOwner: () {},
  );
  try {
    while (!placement.isReady) {
      placement.advance(maxParts: 1);
    }
    return placement.takePlacement();
  } finally {
    placement.close();
  }
}

ForumBodyRubyTreeEmphasisMetrics rubyTreeEmphasisMetricsFixture(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final bands = rubyGlyphTreeBandsFixture(
    html,
    cache,
    direction: direction,
    scaler: scaler,
  );
  final fonts = ForumBodyRubyEmptyAnnotationFontsPreparation(
    bands: bands,
    cache: cache,
    ensureOwner: () {},
    expectedTextScaler: scaler,
  );
  late ForumBodyRubyEmptyAnnotationFonts empty;
  try {
    while (!fonts.isReady) {
      fonts.advance(maxParts: 1);
    }
    empty = fonts.takeFonts();
  } finally {
    fonts.close();
  }
  final metrics = ForumBodyRubyTreeEmphasisMetricsPreparation(
    emptyFonts: empty,
    cache: cache,
    ensureOwner: () {},
    expectedTextScaler: scaler,
  );
  try {
    while (!metrics.isReady) {
      metrics.advance(maxParts: 1);
    }
    return metrics.takeMetrics();
  } finally {
    metrics.close();
  }
}

/// Real parser/source/measurement pipeline shared by tree-format tests. A
/// request transform can attach an actual band before measuring that same graph.
ForumBodyRubyGlyphTreeBands rubyGlyphTreeBandsFixture(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  String sourceId = 'ruby-glyph-tree-fixture',
  String fontRevision = 'ruby-glyph-tree-ahem',
  ForumBodyRubyGlyphTreeInput Function(ForumBodyRubyGlyphTreeInput)? mapInput,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: sourceId,
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: fontRevision,
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  ForumBodyRubyGroupContent? group;
  try {
    while (!flow.isComplete && group == null) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        group = content.parts.whereType<ForumBodyInlineFlowRuby>().first.group;
      }
    }
  } finally {
    flow.close();
  }
  final source = ForumBodyRubyGlyphTreeInputPreparation(
    group: group!,
    maxWidth: 500,
    ensureOwner: () {},
  );
  late ForumBodyRubyGlyphTreeInput input;
  try {
    while (!source.isReady) {
      source.advance(maxParts: 1);
    }
    input = source.takeInput();
  } finally {
    source.close();
  }
  input = mapInput?.call(input) ?? input;
  final measure = ForumBodyRubyGlyphTreeMetricsPreparation(
    input: input,
    cache: cache,
    ensureOwner: () {},
    textScaler: scaler,
  );
  late ForumBodyRubyGlyphTreeMetrics metrics;
  try {
    while (!measure.isReady) {
      measure.advance(maxParts: 1);
    }
    metrics = measure.takeMetrics();
  } finally {
    measure.close();
  }
  final positions = ForumBodyRubyGlyphTreeGeometryPreparation(
    metrics: metrics,
    ensureOwner: () {},
  );
  late ForumBodyRubyGlyphTreeGeometry geometry;
  try {
    while (!positions.isReady) {
      positions.advance(maxParts: 1);
    }
    geometry = positions.takeGeometry();
  } finally {
    positions.close();
  }
  final bands = ForumBodyRubyGlyphTreeBandsPreparation(
    geometry: geometry,
    ensureOwner: () {},
  );
  try {
    while (!bands.isReady) {
      bands.advance(maxParts: 1);
    }
    return bands.takeBands();
  } finally {
    bands.close();
  }
}
