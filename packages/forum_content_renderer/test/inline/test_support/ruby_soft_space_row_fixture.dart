import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_pairing.dart';

/// One actual root with two original RBs/RTs at each RTC rank. Only real source
/// whitespace forms the middle atom; it never supplies another base or RT.
final class RubySoftSpaceRowFixture {
  RubySoftSpaceRowFixture({
    this.direction = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
    int ranks = 1,
    double gapSize = 40,
    bool baseGap = false,
    bool annotationGap = true,
    bool emptyAnnotations = false,
    bool flipLastSide = false,
    double lineHeight = 1,
  }) {
    final reader = ForumBodyReaderStyle(
      textStyle: TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: lineHeight,
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    );
    final doc = const ForumBodyParser().parse(
      html:
          '<p dir="${direction.name}"><ruby style="font-size:${baseGap ? gapSize : 20}px">'
          '<rb style="font-size:20px">A</rb>${baseGap ? ' ' : ''}'
          '<rb style="font-size:20px">B</rb>'
          '${List.generate(ranks, (i) => '<rtc style="font-size:${annotationGap ? gapSize : 10}px;${flipLastSide && i == ranks - 1 ? 'ruby-position:${i.isEven ? 'under' : 'over'}' : ''}">'
              '<rt style="font-size:${ranks == 1 ? 10 : 1}px">${emptyAnnotations ? '' : 'x'}</rt>'
              '${annotationGap ? ' ' : ''}'
              '<rt style="font-size:${ranks == 1 ? 10 : 1}px">${emptyAnnotations ? '' : 'y'}</rt>'
              '</rtc>').join()}'
          '</ruby></p>',
      sourceId: 'actual-soft-space-row',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(doc, reader);
    final flow = ForumBodyStyledFlowCursor(document: doc, reader: reader);
    late final ForumBodyRubyGroupContent group;
    try {
      while (flow.moveNext()) {
        if (flow.current!.node.path == '0/0' &&
            flow.current!.phase == ForumBodyFlowPhase.open) {
          break;
        }
      }
      final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
      try {
        ForumBodyRubyGroupContent? parsed;
        for (var i = 0; !cursor.isComplete && i < 10000; i++) {
          final step = cursor.advance(maxEvents: 1);
          expect(step.workDone, lessThanOrEqualTo(1));
          if (step.hasOutput) parsed = cursor.current;
        }
        expect(cursor.isComplete, isTrue);
        group = parsed!;
      } finally {
        cursor.close();
      }
    } finally {
      flow.close();
    }
    final pairing = ForumBodyRubyAnnotationPairing(
      group: group,
      baseColumnCount: 2,
    );
    sides = pairing.levels.map((l) => l.side).toList();
    final bases = group.base.whereType<ForumBodyRubyBaseContent>().toList();
    final baseSpaces = group.base
        .whereType<ForumBodyRubyTextContent>()
        .map((t) => t.content)
        .toList();
    ForumBodyParagraphContent text(
      List<ForumBodyRubyInlineContent> parts,
      ForumBodyResolvedStyle style,
    ) => parts.isEmpty
        ? ForumBodyParagraphContent.anonymousInline(
            identity: group.identity,
            fontRevision: group.fontRevision,
            styleRevision: group.styleRevision,
            style: style,
          )
        : (parts.single as ForumBodyRubyTextContent).content;
    columnParts = [
      for (var i = 0; i < 2; i++)
        [
          text(bases[i].parts, bases[i].style),
          for (final level in pairing.levels)
            switch (level.spans[i].box) {
              ForumBodyRubyExplicitAnnotationInput(:final annotation) => text(
                annotation.parts,
                annotation.style,
              ),
              _ => throw StateError(
                'Fixture requires two original RTs per rank',
              ),
            },
        ],
    ];
    softSpace = ForumBodyRubySoftSpaceRequest(
      beforeColumn: 1,
      direction: direction,
      sides: sides,
      members: [
        for (final gap in baseSpaces)
          (
            request: ForumBodyTextRequest.paragraph(gap),
            annotationIndex: null,
            gap: 0,
          ),
        for (final (rank, level) in pairing.levels.indexed)
          for (final gap in level.gaps)
            (
              request: ForumBodyTextRequest.paragraph(gap.content),
              annotationIndex: rank,
              gap: 0,
            ),
      ],
    );
    final display = [
      ...columnParts[0].where((c) => !c.isSourceFree),
      ...softSpace.nativeRequests.map((r) => r.content),
      ...columnParts[1].where((c) => !c.isSourceFree),
    ];
    final indices = Map<ForumBodyParagraphContent, int>.identity();
    for (final (i, c) in display.indexed) {
      indices[c] = i;
    }
    final sourceOrder = [
      indices[columnParts[0].first]!,
      for (final c in baseSpaces) indices[c]!,
      indices[columnParts[1].first]!,
      for (final (rank, level) in pairing.levels.indexed) ...[
        if (!columnParts[0][rank + 1].isSourceFree)
          indices[columnParts[0][rank + 1]]!,
        for (final gap in level.gaps) indices[gap.content]!,
        if (!columnParts[1][rank + 1].isSourceFree)
          indices[columnParts[1][rank + 1]]!,
      ],
    ];
    var offset = 0;
    final ranges = <({int startUtf16, int endUtf16})>[];
    for (final parts in [
      columnParts[0],
      softSpace.nativeRequests.map((r) => r.content).toList(),
      columnParts[1],
    ]) {
      final start = offset;
      for (final part in parts) {
        offset += part.projection.text.length;
      }
      ranges.add((startUtf16: start, endUtf16: offset));
    }
    content = ForumBodyInlineSpanContent.compose(
      identity: group.identity,
      path: '0',
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: styles.byPath['0']!,
      contexts: display,
      atomicRanges: ranges,
      softSpaceAtoms: {1},
      sourceOrder: sourceOrder,
    );
    columns = [
      for (final parts in columnParts)
        ForumBodyRubyColumnRequest.layers(
          base: ForumBodyTextRequest.paragraph(parts.first),
          annotations: [
            for (var r = 0; r < sides.length; r++)
              (
                request: ForumBodyTextRequest.paragraph(parts[r + 1]),
                gap: 0.0,
                side: sides[r],
              ),
          ],
        ),
    ];
    columnMetrics = [for (final c in columns) _measureColumn(c)];
    final measured = <ForumBodyRubySoftSpaceMeasuredMember>[];
    for (final m in softSpace.members) {
      final lease = native(m.request.content);
      try {
        measured.add(
          ForumBodyRubySoftSpaceMeasuredMember(
            annotationIndex: m.annotationIndex,
            font: ForumBodyRubyAnnotationMetrics.measure(
              cache: cache,
              lease: lease,
              gap: m.gap,
              side: m.annotationIndex == null
                  ? ForumBodyRubySide.over
                  : sides[m.annotationIndex!],
            ),
          ),
        );
      } finally {
        lease.release();
      }
    }
    spaceMetrics = ForumBodyRubySoftSpaceMetrics.compose(
      members: measured,
      sides: sides,
      direction: direction,
    );
    expect(cache.activeLeases, 0);
  }
  final TextDirection direction;
  final TextScaler textScaler;
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 64 << 20,
  );
  late final List<ForumBodyRubySide> sides;
  late final List<List<ForumBodyParagraphContent>> columnParts;
  late final List<ForumBodyRubyColumnRequest> columns;
  late final List<ForumBodyRubyGroupMetrics> columnMetrics;
  late final ForumBodyRubySoftSpaceRequest softSpace;
  late final ForumBodyRubySoftSpaceMetrics spaceMetrics;
  late final ForumBodyInlineSpanContent content;
  List<ForumBodyRubyAtomMetrics> get atoms => [
    ForumBodyRubyAtomMetrics.column(columnMetrics[0]),
    ForumBodyRubyAtomMetrics.softSpace(spaceMetrics),
    ForumBodyRubyAtomMetrics.column(columnMetrics[1]),
  ];
  List<int> get offsets =>
      content.projection.atoms.map((a) => a.engineUtf16).toList();

  ForumBodyTextLease native(ForumBodyParagraphContent c) =>
      ForumBodyTextRequest.paragraph(
        c,
      ).acquire(cache, width: 2000, textScaler: textScaler, cachedOnly: false)!;
  ForumBodyRubyGroupMetrics _measureColumn(ForumBodyRubyColumnRequest request) {
    final job = ForumBodyRubyGroupPreparation.forLayerMetrics(
      cache: cache,
      base: request.base,
      annotations: request.annotations,
      ensureOwner: () {},
      textScaler: textScaler,
    );
    try {
      while (!job.isReady) {
        job.advance(maxParts: 7);
      }
      return job.takeMetrics();
    } finally {
      job.close();
    }
  }

  ForumBodyInlineParagraphLease parent(
    double width,
    List<PlaceholderDimensions> dims,
  ) => cache.acquireInline(
    content: content,
    width: width,
    dimensions: dims,
    textScaler: textScaler,
  );
  void close() {
    cache.close();
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  }
}
