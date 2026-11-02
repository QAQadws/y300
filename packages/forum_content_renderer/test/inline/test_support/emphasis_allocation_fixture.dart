import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _body =
    '<span style="text-emphasis:none;font-size:31px">大</span>AB '
    '<span style="font-size:31px">؀</span><span style="text-emphasis-position:under">A</span> '
    'e<b style="font-size:31px">́</b> '
    '<span style="text-emphasis-position:under">👩‍👩‍👧‍👦</span> 中\n\n';

class EmphasisAllocationRowFixture {
  const EmphasisAllocationRowFixture(this.view, this.physical, this.metrics);
  final ForumBodyParagraphRowView view;
  final List<ForumBodyParagraphPhysicalLineSelector> physical;
  final ForumBodyEmphasisLineMetrics metrics;
}

class EmphasisAllocationFixture {
  EmphasisAllocationFixture({
    String body = _body,
    String height = '.4',
    double size = 20,
    String font = 'Ahem',
    this.width = 140,
    this.scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
    bool emphasis = true,
    bool shadows = false,
    bool indent = false,
    double? tracking,
  }) {
    addTearDown(cache.close);
    final doc = const ForumBodyParser().parse(
      html:
          '<p style="white-space:pre-wrap;line-height:$height;'
          'text-emphasis:${emphasis ? "'X' red" : 'none'}">$body</p>',
      sourceId: 'row-allocation',
      conversionIdentity: 'none',
    );
    final original = const ForumBodyParagraphContentBuilder().build(
      document: doc,
      path: '0',
      styles: const ForumBodyStyleResolver().resolve(
        doc,
        ForumBodyReaderStyle(
          textStyle: TextStyle(
            fontFamily: font,
            fontSize: size,
            color: const Color(0xff123456),
            letterSpacing: tracking,
            shadows: shadows
                ? const [
                    Shadow(
                      color: Color(0xffaa0000),
                      offset: Offset(2, -3),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          fontRevision: 'row-allocation-test',
          linkColor: const Color(0xff0000ff),
          textDirection: direction,
          firstLineIndent: ForumBodyLength(
            indent ? 2 : 0,
            ForumBodyLengthUnit.em,
          ),
        ),
      ),
    );
    final glyphJob = ForumBodyEmphasisGlyphPreparation(content: original);
    while (!glyphJob.isReady) {
      glyphJob.advance(maxParts: 1);
    }
    glyphs = glyphJob.takeInput();
    natural = cache.acquire(
      content: glyphs.glyphs,
      width: width,
      textScaler: scaler,
    );
    isolated = cache.acquire(
      content: glyphs.glyphs,
      width: width,
      textScaler: scaler,
      rowIsolationPitch: 256,
    );
    final ref = ForumBodyParagraphRowReferencePreparation(
      natural: natural,
      isolated: isolated,
      ensureOwner: () {},
    );
    while (!ref.isReady) {
      ref.advance(maxParts: 17);
    }
    reference = ref.takeReference();
    naturalFrames = _frames(natural);
    isolatedFrames = _frames(isolated);
  }
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 24,
  );
  final double width;
  final TextScaler scaler;
  late final ForumBodyEmphasisGlyphInput glyphs;
  late final ForumBodyParagraphLease natural, isolated;
  late final ForumBodyParagraphRowReference reference;
  late final ForumBodyParagraphLineFrames naturalFrames, isolatedFrames;
  EmphasisAllocationRowFixture row(int start) {
    final j = ForumBodyParagraphRowPreparation(
      parent: isolated,
      startLine: start,
      ensureOwner: () {},
    );
    while (!j.isReady) {
      j.advance(maxParts: 1);
    }
    final row = j.takeMetrics(),
        view = ForumBodyParagraphRowView.bind(
          parent: isolated,
          metrics: row,
          ensureOwner: () {},
        );
    final source = ForumBodyEmphasisRowInputPreparation(
      parentGlyphInput: glyphs,
      row: row,
    );
    while (!source.isReady) {
      source.advance(maxParts: 1);
    }
    final measurement = ForumBodyEmphasisLineMetricsPreparation.row(
      input: source.takeInput(),
      cache: cache,
      ensureOwner: () {},
      textScaler: scaler,
    );
    for (var n = 0; !measurement.isReady && n < 20000; n++) {
      final step = measurement.advance(maxParts: 1);
      expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesRecorded, 0);
      expect(step.waitingForLayoutBudget, isFalse);
    }
    expect(measurement.isReady, isTrue);
    final metrics = measurement.takeMetrics();
    final p = ForumBodyParagraphPhysicalLinePreparation(
      group: view,
      frames: isolatedFrames,
      ensureOwner: () {},
    );
    while (!p.isReady) {
      p.advance(maxParts: 1);
    }
    return EmphasisAllocationRowFixture(view, p.takeSelectors(), metrics);
  }

  ForumBodyEmphasisRowAllocationPreparation prepare(
    EmphasisAllocationRowFixture row, {
    void Function()? owner,
    int maxLines = 64,
    int maxMarks = 512,
    double maxHeight = 1048576,
    List<ForumBodyParagraphPhysicalLineSelector>? physical,
    ForumBodyParagraphLineFrames? naturalTable,
  }) => ForumBodyEmphasisRowAllocationPreparation(
    source: row.metrics,
    reference: reference,
    naturalFrames: naturalTable ?? naturalFrames,
    isolatedFrames: isolatedFrames,
    physicalLines: physical ?? row.physical,
    ensureOwner: owner ?? () {},
    maxLines: maxLines,
    maxMarks: maxMarks,
    maxHeight: maxHeight,
  );
}

ForumBodyParagraphLineFrames _frames(ForumBodyParagraphLease p) {
  final j = ForumBodyParagraphLineFramePreparation(
    parent: p,
    ensureOwner: () {},
  );
  while (!j.isReady) {
    j.advance(maxParts: 17);
  }
  return j.takeFrames();
}
