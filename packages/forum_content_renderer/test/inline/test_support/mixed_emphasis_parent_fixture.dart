import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';

const mixedEmphasisChildren = [
  '<ruby style="text-emphasis:none">A<rt>x</rt></ruby>',
  '<ruby>A<rt style="text-emphasis:triangle">x</rt></ruby>',
  '<ruby>A<rt style="font-size:5px">x</rt>B<rt style="font-size:30px">y</rt></ruby>',
  '<ruby style="text-emphasis:none"><rb>A</rb><rb>B</rb><rtc><rt>x</rt></rtc><rtc>word</rtc></ruby>',
  '<ruby style="font-size:12px;text-emphasis:none"><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
  '<ruby style="text-emphasis:none"><rb>A</rb> <rb>B</rb><rtc><rt>x</rt> <rt>y</rt></rtc></ruby>',
];

final class MixedEmphasisCurve extends TextScaler {
  const MixedEmphasisCurve();
  @override
  double scale(double size) => size * (size < 25 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

typedef MixedEmphasisAllocatedSource = ({
  ForumBodyInlineEmphasisRowAllocation allocation,
  ForumBodyInlineParagraphLease natural,
  ForumBodyInlineParagraphLease source,
});

/// Actual whole-source measurement/isolation/allocation, without acquiring
/// paint layers. Both returned parents stay borrowed by the tested operation.
MixedEmphasisAllocatedSource measureMixedEmphasisAllocatedSource(
  MixedEmphasisParentFixture fixture,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
}) {
  final parent = ForumBodyInlineEmphasisParentPreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    while (!parent.isReady) {
      parent.advance(maxParts: 32);
    }
    final natural = parent.takeMeasurement();
    addTearDown(natural.parent.release);
    final iso = ForumBodyInlineEmphasisIsolationPreparation(
      metrics: natural.metrics,
      natural: natural.parent,
      cache: cache,
      ensureOwner: () {},
    );
    try {
      while (!iso.isReady) {
        iso.advance(maxParts: 32);
      }
      final isolated = iso.takeMeasurement();
      addTearDown(isolated.parent.release);
      final work = ForumBodyInlineEmphasisRowAllocationPreparation(
        input: isolated.metrics,
        natural: natural.parent,
        isolated: isolated.parent,
        ensureOwner: () {},
      );
      try {
        while (!work.isReady) {
          work.advance(maxParts: 32);
        }
        return (
          allocation: work.takeAllocation(),
          natural: natural.parent,
          source: isolated.parent,
        );
      } finally {
        work.close();
      }
    } finally {
      iso.close();
    }
  } finally {
    parent.close();
  }
}

typedef MixedEmphasisParentMeasurement = ({
  ForumBodyInlinePageContent content,
  ForumBodyInlineParagraphLease lease,
});

/// Actual parser/flow/source preparation; parent and children keep one original
/// source namespace. The final active-parent visible format is not synthesized.
final class MixedEmphasisParentFixture {
  MixedEmphasisParentFixture(
    String child, {
    this.width = 300,
    TextDirection direction = TextDirection.ltr,
    ForumBodyParagraphLayoutMode? layoutMode,
    String parentStyle = 'text-emphasis:circle;line-height:.4',
    String prefix = 'P',
    String suffix = 'Q',
    TextStyle readerTextStyle = const TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      color: Color(0xff123456),
    ),
  }) {
    final doc = const ForumBodyParser().parse(
      html:
          '<p dir="${direction.name}" style="$parentStyle"><span>$prefix</span>$child<span>$suffix</span></p>',
      sourceId: 'mixed-emphasis-parent',
      conversionIdentity: 'none',
    );
    final reader = ForumBodyReaderStyle(
      textStyle: readerTextStyle,
      fontRevision: 'mixed-emphasis-parent',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    );
    final flow = ForumBodyTextFlowCursor(document: doc, reader: reader);
    ForumBodyInlineFlowContent? actual;
    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        if (flow.current case ForumBodyTextFlowInline(:final content)) {
          actual = content;
          break;
        }
      }
    } finally {
      flow.close();
    }
    input = ForumBodyInlinePlanInput(
      layoutMode == null
          ? actual!
          : ForumBodyInlineFlowContent(
              identity: actual!.identity,
              path: actual.path,
              fontRevision: actual.fontRevision,
              styleRevision: actual.styleRevision,
              style: actual.style,
              layoutMode: layoutMode,
              parts: actual.parts,
              ignored: actual.ignored,
              issues: actual.issues,
            ),
      width,
    );
  }
  final double width;
  late final ForumBodyInlinePlanInput input;
  ForumBodyInlinePlanPreparation open(
    ForumBodyParagraphCache cache, {
    TextScaler scaler = TextScaler.noScaling,
    void Function()? guard,
  }) => ForumBodyInlinePlanPreparation(
    input: input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: guard ?? () {},
  );

  ({MixedEmphasisParentMeasurement value, int parts}) finish(
    ForumBodyInlinePlanPreparation job,
    ForumBodyParagraphCache cache, {
    int quantum = 1,
    bool cachedOnly = false,
  }) {
    var parts = 0;
    try {
      for (var n = 0; !job.isReady; n++) {
        expect(n, lessThan(50000));
        final before = (cache.layoutBuildCount, cache.pictureBuildCount);
        final s = job.advance(maxParts: quantum, cachedOnly: cachedOnly);
        expect(s.partsPrepared, inInclusiveRange(1, quantum));
        expect(s.waitingForLayoutBudget, isFalse);
        expect(job.cacheMiss, isFalse);
        expect(cache.layoutBuildCount - before.$1, lessThanOrEqualTo(1));
        expect(cache.pictureBuildCount, before.$2);
        parts += s.partsPrepared;
      }
      expect(job.isReady, isTrue);
      return (value: job.take(), parts: parts);
    } finally {
      job.close();
    }
  }
}
