import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class RubyEmphasisNonlinearScaler extends TextScaler {
  const RubyEmphasisNonlinearScaler();
  @override
  double scale(double size) => size < 20 ? size * 1.45 : size * 1.12;
  @override
  double get textScaleFactor => throw StateError('Use per-size values');
}

typedef RubyEmphasisFixture = ({
  ForumBodyParagraphContent base,
  List<ForumBodyParagraphContent> annotations,
  List<ForumBodyParagraphContent> emptyAnnotations,
});

RubyEmphasisFixture rubyEmphasisFixture({
  String text =
      'ffi 中 é <span style="font-size:15px;text-emphasis-position:under">'
      'الع 👩‍👩‍👧‍👦</span>',
  String emphasis = "'X' red",
  double size = 20,
  double height = .4,
  bool paintEffects = false,
  TextDirection direction = TextDirection.ltr,
  ForumBodyParagraphLayoutMode mode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
}) {
  final annotationHtml = [
    for (final empty in [false, true])
      for (var i = 0; i < 3; i++)
        '<p style="font-size:${8 + i * 3}px;line-height:.4">'
            '${empty ? '' : '注音'}</p>',
  ].join();
  final document = const ForumBodyParser().parse(
    html:
        '<p style="font-size:${size}px;line-height:$height;'
        'text-emphasis:$emphasis">$text</p>$annotationHtml',
    sourceId: 'ruby-base-emphasis',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: const Color(0xff123456),
        shadows: paintEffects
            ? const [
                Shadow(
                  color: Color(0xff880011),
                  offset: Offset(2.5, -3.25),
                  blurRadius: 1.5,
                ),
              ]
            : null,
        backgroundColor: paintEffects ? const Color(0x4033cc55) : null,
        decoration: paintEffects ? TextDecoration.underline : null,
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  ForumBodyParagraphContent build(
    String path,
    ForumBodyParagraphLayoutMode mode,
  ) => const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: path,
    layoutMode: mode,
  );
  return (
    base: build('0', mode),
    annotations: [
      for (var i = 1; i <= 3; i++)
        build('$i', ForumBodyParagraphLayoutMode.intrinsicSingleLine),
    ],
    emptyAnnotations: [
      for (var i = 4; i <= 6; i++)
        build('$i', ForumBodyParagraphLayoutMode.intrinsicSingleLine),
    ],
  );
}

ForumBodyEmphasisLineMetrics measureRubyEmphasisLine(
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
  RubyEmphasisFixture? content,
  ForumBodyTextRequest Function(ForumBodyEmphasisTextInput)? request,
}) {
  final source = ForumBodyEmphasisTextPreparation(
    content: (content ?? rubyEmphasisFixture()).base,
  );
  while (!source.isReady) {
    source.advance(maxParts: 1);
  }
  final input = source.takeInput();
  final job = ForumBodyEmphasisLineMetricsPreparation(
    input: input,
    baseRequest: request?.call(input),
    cache: cache,
    ensureOwner: () {},
    textScaler: scaler,
  );
  addTearDown(job.close);
  while (!job.isReady) {
    final step = job.advance(maxParts: 1);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.picturesRecorded, 0);
    expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  return job.takeMetrics();
}

ForumBodyRubyGroupMetrics measureRubyEmphasisGroup(
  ForumBodyParagraphCache cache,
  ForumBodyEmphasisLineMetrics line, {
  required RubyEmphasisFixture fixture,
  List<ForumBodyRubySide> sides = const [ForumBodyRubySide.over],
  bool empty = false,
}) {
  final base = line.baseRequest.acquire(
    cache,
    width: line.requestWidth,
    textScaler: line.textScaler,
    cachedOnly: false,
  )!;
  final inputs = (empty ? fixture.emptyAnnotations : fixture.annotations)
      .take(sides.length)
      .toList();
  final annotations = <ForumBodyTextLease?>[];
  try {
    for (final input in inputs) {
      annotations.add(
        empty ? null : cache.acquire(content: input, width: line.requestWidth),
      );
    }
    return ForumBodyRubyGroupMetrics.measureLayers(
      cache: cache,
      baseLease: base,
      annotations: [
        for (var i = 0; i < inputs.length; i++)
          (
            content: inputs[i],
            lease: annotations[i],
            side: sides[i],
            gap: (i + 1).toDouble(),
          ),
      ],
    );
  } finally {
    base.release();
    for (final annotation in annotations) {
      annotation?.release();
    }
  }
}
