import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

typedef RubyLayerFixture = ({
  ForumBodyInlineSpanContent content,
  List<ForumBodyParagraphContent> parts,
});

/// Real parser/grammar output: explicit base, RTC ranks, ignored RP sources.
RubyLayerFixture rubyLayerInput({
  String prefix = '',
  String base = 'AB',
  String suffix = '',
  List<(String, double)> annotations = const [('xy', 10), ('z', 15), ('q', 5)],
  String direction = 'ltr',
  double lineHeight = 1,
  bool fallbackDelimiters = false,
}) {
  final reader = ForumBodyReaderStyle(
    textStyle: const TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      height: 1,
      color: Color(0xff000000),
    ),
    fontRevision: 'ahem',
    linkColor: const Color(0xff0000ff),
  );
  final document = const ForumBodyParser().parse(
    html:
        '<p dir="$direction"><span>$prefix</span><ruby><rb style="line-height:$lineHeight">$base</rb>'
        '${annotations.map((part) => '<rtc>${fallbackDelimiters ? '<rp>[</rp>' : ''}<rt style="font-size:${part.$2}px;line-height:$lineHeight">${part.$1}</rt>${fallbackDelimiters ? '<rp>]</rp>' : ''}</rtc>').join()}'
        '</ruby><span>$suffix</span></p>',
    sourceId: 'ruby-layer-view',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(document, reader);
  final flow = ForumBodyStyledFlowCursor(document: document, reader: reader);
  try {
    while (flow.moveNext()) {
      if (flow.current!.node.path == '0/1' &&
          flow.current!.phase == ForumBodyFlowPhase.open) {
        break;
      }
    }
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    try {
      ForumBodyRubyGroupContent? group;
      for (var i = 0; !cursor.isComplete && i < 1000; i++) {
        final step = cursor.advance(maxEvents: 1);
        expect(step.workDone, lessThanOrEqualTo(1));
        if (step.hasOutput) {
          expect(group, isNull);
          group = cursor.current;
        }
      }
      expect(cursor.isComplete, isTrue);
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
      final rb = ruby.base.single as ForumBodyRubyBaseContent;
      ForumBodyParagraphContent annotation(
        ForumBodyRubyAnnotationContent entry,
      ) {
        final rt =
            (entry as ForumBodyRubyAnnotationContainerContent).parts.single
                as ForumBodyRubyTextAnnotationContent;
        return text(rt.parts, rt.style);
      }

      final parts = [
        text(rb.parts, rb.style),
        for (final entry in ruby.annotations) annotation(entry),
      ];
      ForumBodyParagraphContent ordinary(String path) =>
          const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: styles,
            path: path,
            layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          );
      final before = ordinary('0/0');
      return (
        content: ForumBodyInlineSpanContent.compose(
          identity: ruby.identity,
          path: '0',
          fontRevision: ruby.fontRevision,
          styleRevision: ruby.styleRevision,
          style: styles.byPath['0']!,
          contexts: [
            before,
            ...parts.where((part) => !part.isSourceFree),
            ordinary('0/2'),
          ],
          atomicRanges: [
            (
              startUtf16: before.projection.text.length,
              endUtf16:
                  before.projection.text.length +
                  parts.fold(
                    0,
                    (sum, part) => sum + part.projection.text.length,
                  ),
            ),
          ],
        ),
        parts: parts,
      );
    } finally {
      cursor.close();
    }
  } finally {
    flow.close();
  }
}

ForumBodyRubyGroupLayout rubyLayerGroup({
  required ForumBodyParagraphCache cache,
  required List<ForumBodyParagraphContent> parts,
  List<ForumBodyRubySide> sides = const [
    ForumBodyRubySide.over,
    ForumBodyRubySide.under,
    ForumBodyRubySide.over,
  ],
  List<double>? gaps,
  TextScaler textScaler = TextScaler.noScaling,
  ForumBodyRubyLevelMetrics? level,
}) {
  final glyphs = parts
      .where((part) => part.projection.text.isNotEmpty)
      .toList();
  final band = ForumBodyTextBandContent(contexts: glyphs);
  final leases = <ForumBodyTextLease?>[];
  var transferred = false;
  try {
    for (final (index, part) in parts.indexed) {
      leases.add(
        part.projection.text.isNotEmpty
            ? cache.acquireBandChild(
                content: band,
                childIndex: glyphs.indexOf(part),
                textScaler: textScaler,
              )
            : index == 0
            ? cache.acquire(content: part, width: 300, textScaler: textScaler)
            : null,
      );
    }
    for (final lease in leases.whereType<ForumBodyTextBandChildLease>()) {
      cache.prepareBandChildPaint(lease);
    }
    final group = ForumBodyRubyGroupLayout.adoptLayers(
      cache: cache,
      baseLease: leases.first!,
      level: level,
      annotations: [
        for (var i = 1; i < parts.length; i++)
          (
            content: parts[i],
            lease: leases[i],
            gap: gaps?[i - 1] ?? 0.0,
            side: sides[i - 1],
          ),
      ],
    );
    transferred = true;
    return group;
  } finally {
    if (!transferred) {
      for (final lease in leases) {
        lease?.release();
      }
    }
  }
}
