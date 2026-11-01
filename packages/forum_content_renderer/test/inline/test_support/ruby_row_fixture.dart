import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// One actual ruby root, two explicit bases and two real RTs at every RTC rank.
/// Display columns keep an explicit original source permutation; no rebasing.
final class RubyRowFixture {
  RubyRowFixture({
    int ranks = 100,
    bool missingSecond = false,
    bool flipLastSide = false,
    bool equalColumns = false,
    double lineHeight = 1,
    String direction = 'ltr',
    this.textScaler = TextScaler.noScaling,
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
    final document = const ForumBodyParser().parse(
      html:
          '<p dir="$direction"><ruby><rb style="font-size:${equalColumns ? 20 : 30}px;line-height:$lineHeight">A</rb><rb style="font-size:20px;line-height:$lineHeight">B</rb>'
          '${List.generate(ranks, (i) => '<rtc><rt style="font-size:${equalColumns || i.isEven ? 1 : 2}px;line-height:$lineHeight">x$i</rt><rt style="font-size:${equalColumns
              ? 1
              : i.isEven
              ? 2
              : 1}px;line-height:$lineHeight">${missingSecond && i % 17 != 0 ? '' : 'y$i'}</rt></rtc>').join()}'
          '</ruby></p>',
      sourceId: 'ruby-rows',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(document, reader);
    final flow = ForumBodyStyledFlowCursor(document: document, reader: reader);
    ForumBodyRubyGroupContent? group;
    try {
      while (flow.moveNext()) {
        if (flow.current!.node.path == '0/0' &&
            flow.current!.phase == ForumBodyFlowPhase.open) {
          break;
        }
      }
      final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
      try {
        for (var i = 0; !cursor.isComplete && i < 3000; i++) {
          final step = cursor.advance(maxEvents: 1);
          expect(step.workDone, lessThanOrEqualTo(1));
          if (step.hasOutput) {
            expect(group, isNull);
            group = cursor.current;
          }
        }
        expect(cursor.isComplete, isTrue);
      } finally {
        cursor.close();
      }
    } finally {
      flow.close();
    }
    final ruby = group!;
    ForumBodyParagraphContent text(
      List<ForumBodyRubyInlineContent> parts,
      ForumBodyResolvedStyle style,
    ) => parts.isEmpty
        ? ForumBodyParagraphContent.anonymousInline(
            identity: ruby.identity,
            fontRevision: ruby.fontRevision,
            styleRevision: ruby.styleRevision,
            style: style,
          )
        : (parts.single as ForumBodyRubyTextContent).content;
    final bases = [
      for (final rb in ruby.base.cast<ForumBodyRubyBaseContent>())
        text(rb.parts, rb.style),
    ];
    final layers = [
      for (final rtc
          in ruby.annotations.cast<ForumBodyRubyAnnotationContainerContent>())
        [
          for (final rt in rtc.parts.cast<ForumBodyRubyTextAnnotationContent>())
            text(rt.parts, rt.style),
        ],
    ];
    parts = [
      for (var column = 0; column < 2; column++)
        [bases[column], for (final layer in layers) layer[column]],
    ];
    final display = [for (final column in parts) ...column];
    final sourceOrder = [
      0,
      ranks + 1,
      for (var rank = 0; rank < ranks; rank++) ...[rank + 1, ranks + rank + 2],
    ];
    final glyphs = [
      for (final index in sourceOrder)
        if (display[index].projection.text.isNotEmpty) display[index],
    ];
    final requests =
        Map<ForumBodyParagraphContent, ForumBodyTextRequest>.identity();
    for (var start = 0; start < glyphs.length; start += 64) {
      final band = ForumBodyTextBandContent(
        contexts: glyphs.sublist(start, (start + 64).clamp(0, glyphs.length)),
      );
      for (var i = 0; i < band.contexts.length; i++) {
        requests[band.contexts[i]] = ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: i,
        );
      }
    }
    var offset = 0;
    final atoms = <({int startUtf16, int endUtf16})>[];
    for (final column in parts) {
      final start = offset;
      offset += column.fold(
        0,
        (sum, part) => sum + part.projection.text.length,
      );
      atoms.add((startUtf16: start, endUtf16: offset));
    }
    content = ForumBodyInlineSpanContent.compose(
      identity: ruby.identity,
      path: '0',
      fontRevision: ruby.fontRevision,
      styleRevision: ruby.styleRevision,
      style: styles.byPath['0']!,
      contexts: display.where((part) => !part.isSourceFree).toList(),
      atomicRanges: atoms,
      sourceOrder: missingSecond
          ? _withoutAnonymous(display, sourceOrder)
          : sourceOrder,
    );
    columns = [
      for (final column in parts)
        ForumBodyRubyColumnRequest.layers(
          base: requests[column.first]!,
          annotations: [
            for (var rank = 0; rank < ranks; rank++)
              (
                request:
                    requests[column[rank + 1]] ??
                    ForumBodyTextRequest.paragraph(column[rank + 1]),
                gap: 0.0,
                side: rank.isEven != (flipLastSide && rank == ranks - 1)
                    ? ForumBodyRubySide.over
                    : ForumBodyRubySide.under,
              ),
          ],
        ),
    ];
    metrics = [for (final column in columns) _measure(column)];
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
  }
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  final TextScaler textScaler;
  late final List<List<ForumBodyParagraphContent>> parts;
  late final ForumBodyInlineSpanContent content;
  late final List<ForumBodyRubyColumnRequest> columns;
  late final List<ForumBodyRubyGroupMetrics> metrics;
  final _leases = <ForumBodyInlineParagraphLease>[];
  final _views = <ForumBodyInlineParagraphView>[];
  ForumBodyRubyGroupMetrics _measure(ForumBodyRubyColumnRequest column) {
    final prepare = ForumBodyRubyGroupPreparation.forLayerMetrics(
      cache: cache,
      base: column.base,
      annotations: column.annotations,
      ensureOwner: () {},
      textScaler: textScaler,
    );
    try {
      while (!prepare.isReady) {
        prepare.advance(maxParts: 7);
      }
      return prepare.takeMetrics();
    } finally {
      prepare.close();
    }
  }

  ForumBodyInlineParagraphLease parent(
    double width, [
    List<PlaceholderDimensions>? dimensions,
  ]) {
    final lease = cache.acquireInline(
      content: content,
      width: width,
      dimensions:
          dimensions ??
          [for (final item in metrics) item.placeholderDimensions],
      textScaler: textScaler,
    );
    _leases.add(lease);
    return lease;
  }

  ForumBodyInlineParagraphView view(
    ForumBodyInlineParagraphLease parent,
    List<ForumBodyRubyLevelMetrics?> targets,
  ) {
    final groups = <int, ForumBodyRubyGroupLayout>{};
    var transferred = false;
    try {
      for (var column = 0; column < columns.length; column++) {
        final input = columns[column];
        final prepare = ForumBodyRubyGroupPreparation.fromLayerRequests(
          cache: cache,
          base: input.base,
          annotations: input.annotations,
          level: targets[column],
          ensureOwner: () {},
          textScaler: textScaler,
        );
        try {
          while (!prepare.isReady) {
            prepare.advance(maxParts: 7);
          }
          groups[column] = prepare.takeLayout();
        } finally {
          prepare.close();
        }
      }
      final result = ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubyGroups: groups,
      );
      _views.add(result);
      transferred = true;
      return result;
    } finally {
      if (!transferred) {
        for (final group in groups.values) {
          group.close();
        }
        parent.release();
      }
    }
  }

  void close() {
    for (final view in _views) {
      view.close();
    }
    for (final lease in _leases) {
      lease.release();
    }
    cache.close();
  }
}

List<int> _withoutAnonymous(
  List<ForumBodyParagraphContent> display,
  List<int> order,
) {
  final map = <int, int>{};
  var next = 0;
  for (final (index, part) in display.indexed) {
    if (!part.isSourceFree) map[index] = next++;
  }
  return [
    for (final index in order)
      if (map.containsKey(index)) map[index]!,
  ];
}
