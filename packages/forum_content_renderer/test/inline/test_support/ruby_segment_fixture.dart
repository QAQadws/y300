import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_pairing.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';

/// Actual two-RB HTML with original explicit and anonymous annotation boxes.
/// Native members remain independent; the real pairing supplies their spans.
final class RubySegmentFixture {
  RubySegmentFixture({
    bool dense = false,
    this.direction = TextDirection.ltr,
    String position = 'alternate',
    double lineHeight = 1,
    this.textScaler = TextScaler.noScaling,
  }) {
    final doc = const ForumBodyParser().parse(
      html:
          '<p dir="${direction.name}"><ruby style="ruby-position:$position">'
          '<rb style="font-size:20px;line-height:$lineHeight">A</rb>'
          '<rb style="font-size:30px;line-height:$lineHeight">B</rb>'
          '${dense ? List.generate(100, (i) => '<rtc style="font-size:1px;line-height:$lineHeight">r$i</rtc>').join() : '<rtc><rt style="font-size:10px;line-height:$lineHeight">xx</rt><rt style="font-size:15px;line-height:$lineHeight">yy</rt></rtc><rtc style="font-size:10px;line-height:$lineHeight">abcdefghij</rtc><rtc style="font-size:8px;line-height:$lineHeight">outer</rtc>'}'
          '</ruby></p>',
      sourceId: 'actual-ruby-segment',
      conversionIdentity: 'none',
    );
    final flow = ForumBodyStyledFlowCursor(
      document: doc,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    ForumBodyRubyGroupContent? source;
    try {
      while (flow.moveNext()) {
        if (flow.current!.node is ForumBodyElement &&
            (flow.current!.node as ForumBodyElement).kind ==
                ForumBodyElementKind.ruby &&
            flow.current!.phase == ForumBodyFlowPhase.open) {
          break;
        }
      }
      final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
      try {
        for (var i = 0; !cursor.isComplete && i < 5000; i++) {
          final step = cursor.advance(maxEvents: 1);
          expect(step.workDone, lessThanOrEqualTo(1));
          if (step.hasOutput) {
            expect(source, isNull);
            source = cursor.current;
          }
        }
        expect(cursor.isComplete, isTrue);
      } finally {
        cursor.close();
      }
    } finally {
      flow.close();
    }
    final group = source!;
    final paired = ForumBodyRubyAnnotationPairing(
      group: group,
      baseColumnCount: 2,
    );
    bases = [
      for (final rb in group.base.cast<ForumBodyRubyBaseContent>())
        (rb.parts.single as ForumBodyRubyTextContent).content,
    ];
    annotations = [
      for (final level in paired.levels)
        for (final span in level.spans)
          switch (span.box) {
            ForumBodyRubyExplicitAnnotationInput(:final annotation) =>
              (annotation.parts.single as ForumBodyRubyTextContent).content,
            ForumBodyRubyAnonymousAnnotationInput(:final content) => content,
          },
    ];
    final contents = [...bases, ...annotations];
    for (var start = 0; start < contents.length; start += 64) {
      final band = ForumBodyTextBandContent(
        contexts: contents.sublist(
          start,
          (start + 64).clamp(0, contents.length),
        ),
      );
      for (var i = 0; i < band.contexts.length; i++) {
        _requests[band.contexts[i]] = ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: i,
        );
        _leases[band.contexts[i]] = cache.acquireBandChild(
          content: band,
          childIndex: i,
          textScaler: textScaler,
        );
      }
    }
    sides = paired.levels.map((level) => level.side).toList();
    empty = ForumBodyParagraphContent.anonymousInline(
      identity: group.identity,
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: group.style,
    );
    rawColumns = [
      for (final base in bases)
        ForumBodyRubyGroupMetrics.measureLayers(
          cache: cache,
          baseLease: lease(base),
          annotations: [
            for (final side in sides)
              (content: empty, lease: null, gap: 0.0, side: side),
          ],
        ),
    ];
    var index = 0;
    measured = [
      for (final (rank, level) in paired.levels.indexed)
        for (final span in level.spans)
          ForumBodyRubyMeasuredSpan(
            startColumn: span.startColumn,
            endColumn: span.endColumn,
            annotationIndex: rank,
            annotation: ForumBodyRubyAnnotationMetrics.measure(
              cache: cache,
              lease: lease(annotations[index++]),
              side: level.side,
            ),
          ),
    ];
    expect(cache.pictureBuildCount, 0);
  }
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  final TextDirection direction;
  final TextScaler textScaler;
  late final List<ForumBodyParagraphContent> bases;
  late final List<ForumBodyParagraphContent> annotations;
  late final List<ForumBodyRubySide> sides;
  late final ForumBodyParagraphContent empty;
  late final List<ForumBodyRubyGroupMetrics> rawColumns;
  late final List<ForumBodyRubyMeasuredSpan> measured;
  final _leases =
      Map<ForumBodyParagraphContent, ForumBodyTextBandChildLease>.identity();
  final _requests =
      Map<ForumBodyParagraphContent, ForumBodyTextRequest>.identity();
  final _layouts = <ForumBodyRubySegmentLayout>[];
  ForumBodyTextBandChildLease lease(ForumBodyParagraphContent content) =>
      _leases[content]!;

  ForumBodyRubySegmentRequest request({bool individual = false}) {
    ForumBodyTextRequest get(ForumBodyParagraphContent content) => individual
        ? ForumBodyTextRequest.paragraph(content)
        : _requests[content]!;
    return ForumBodyRubySegmentRequest(
      bases: [for (final base in bases) get(base)],
      sides: sides,
      spans: [
        for (var i = 0; i < measured.length; i++)
          (
            request: get(annotations[i]),
            startColumn: measured[i].startColumn,
            endColumn: measured[i].endColumn,
            annotationIndex: measured[i].annotationIndex,
            gap: measured[i].annotation.gap,
          ),
      ],
      direction: direction,
    );
  }

  void releaseGlyphs({bool clear = true}) {
    for (final lease in _leases.values) {
      lease.release();
    }
    if (clear) cache.clearUnpinned();
  }

  ForumBodyRubySegmentComposition work({
    List<ForumBodyRubyMeasuredSpan>? spans,
    double maxWidth = 16384,
  }) => ForumBodyRubySegmentComposition(
    columns: rawColumns,
    spans: spans ?? measured,
    direction: direction,
    maxWidth: maxWidth,
  );
  ForumBodyRubySegmentMetrics compose({int quantum = 7}) {
    final job = work();
    for (var i = 0; !job.isComplete && i < 20000; i++) {
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
    }
    expect(job.isComplete, isTrue);
    return job.result;
  }

  List<ForumBodyRubyGroupLayout> prepareColumns(
    ForumBodyRubySegmentMetrics metrics, {
    bool prepareAnnotations = true,
  }) {
    for (final lease in _leases.values) {
      if (prepareAnnotations || bases.contains(lease.content)) {
        cache.prepareBandChildPaint(lease);
      }
    }
    return [
      for (final base in bases)
        ForumBodyRubyGroupLayout.adoptLayers(
          cache: cache,
          baseLease: lease(base),
          level: metrics.level,
          annotations: [
            for (final side in sides)
              (content: empty, lease: null, gap: 0.0, side: side),
          ],
        ),
    ];
  }

  ForumBodyRubySegmentLayout prepare(ForumBodyRubySegmentMetrics metrics) {
    final columns = prepareColumns(metrics);
    final layout = ForumBodyRubySegmentLayout.adopt(
      cache: cache,
      columns: columns,
      spans: [
        for (final content in annotations)
          (content: content, lease: lease(content)),
      ],
      metrics: metrics,
    );
    _layouts.add(layout);
    return layout;
  }

  void close() {
    for (final layout in _layouts) {
      layout.close();
    }
    for (final lease in _leases.values) {
      lease.release();
    }
    cache.close();
  }
}
