import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

/// Real native planning is separate from the reading cache, so tests can
/// distinguish glyph-only planning from visible picture preparation.
final class MixedPagePreparationFixture {
  MixedPagePreparationFixture({
    int pairs = 4,
    bool batched = true,
    double width = 120,
    double height = 30,
    int entries = 2,
    int bytes = 1 << 24,
    bool emptyAnnotations = false,
    List<double>? baselineShifts,
  }) : cache = ForumBodyParagraphCache(
         maxEntries: entries,
         maxEstimatedBytes: bytes,
       ) {
    final roots = [
      for (var i = 0; i < pairs; i++)
        '<span>b$i</span><span style="font-size:10px">${emptyAnnotations || baselineShifts != null ? '' : 'r$i'}</span>',
    ];
    final doc = const ForumBodyParser().parse(
      html: '<p>${roots.join()}</p>',
      sourceId: 'mixed-page-preparation',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          height: 1,
          color: Color(0xff000000),
        ),
        fontRevision: 'loaded',
        linkColor: const Color(0xff0000ff),
      ),
    );
    contexts = [
      for (var i = 0; i < pairs * 2; i++)
        const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: styles,
          path: '0/$i',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ];
    final batchContexts = contexts
        .where((context) => context.projection.text.isNotEmpty)
        .toList();
    final batchIndices = Map<ForumBodyParagraphContent, int>.identity();
    for (final (index, context) in batchContexts.indexed) {
      batchIndices[context] = index;
    }
    final bands = [
      for (var start = 0; start < batchContexts.length; start += 64)
        ForumBodyTextBandContent(
          contexts: batchContexts.sublist(
            start,
            start + 64 < batchContexts.length
                ? start + 64
                : batchContexts.length,
          ),
        ),
    ];
    ForumBodyTextRequest request(int index) {
      final content = contexts[index];
      if (!batched || content.projection.text.isEmpty) {
        return ForumBodyTextRequest.paragraph(content);
      }
      final batchedIndex = batchIndices[content]!;
      return ForumBodyTextRequest.bandChild(
        band: bands[batchedIndex ~/ 64],
        childIndex: batchedIndex % 64,
      );
    }

    var offset = 0;
    final ranges = <({int startUtf16, int endUtf16})>[];
    for (var i = 0; i < pairs; i++) {
      final end =
          offset +
          contexts[i * 2].projection.text.length +
          contexts[i * 2 + 1].projection.text.length;
      ranges.add((startUtf16: offset, endUtf16: end));
      offset = end;
    }
    content = ForumBodyInlineSpanContent.compose(
      identity: doc.identity,
      path: '0',
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: styles.byPath['0']!,
      contexts: contexts,
      atomicRanges: ranges,
    );
    final planning = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 24,
    );
    final composer = ForumBodyTextPageComposer(
      identity: doc.identity,
      layoutId: 'mixed-preparation',
      width: width,
      height: height,
      maxPages: 100,
      maxFragments: 100,
    );
    final dimensions = <PlaceholderDimensions>[];
    final baselineMetrics = <ForumBodyTextBaselineMetrics>[];
    try {
      for (var i = 0; i < pairs; i++) {
        if (baselineShifts != null) {
          final job = ForumBodyTextBaselinePreparation(
            cache: planning,
            request: request(i * 2),
            baselineShift: baselineShifts[i],
            width: 16384,
            textScaler: TextScaler.noScaling,
            ensureOwner: () {},
            preparePaint: false,
          );
          try {
            while (!job.isReady) {
              job.advance(maxParts: 1);
            }
            final metrics = job.takeMetrics();
            baselineMetrics.add(metrics);
            dimensions.add(metrics.placeholderDimensions);
          } finally {
            job.close();
          }
          continue;
        }
        final group = ForumBodyRubyGroupLayout.create(
          cache: planning,
          base: contexts[i * 2],
          annotation: contexts[i * 2 + 1],
        );
        try {
          dimensions.add(group.placeholderDimensions);
        } finally {
          group.close();
        }
      }
      composer.appendInline(
        lease: planning.acquireInline(
          content: content,
          width: width,
          dimensions: dimensions,
        ),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      var work = 0;
      while (!composer.needsInput) {
        if (work++ > 1000) throw StateError('Test planning stalled');
        composer.advance(maxLines: 1);
      }
      composer.finish();
      snapshot = composer.snapshot;
    } finally {
      composer.close();
      planning.close();
    }
    input = baselineShifts != null
        ? ForumBodyInlinePageContent.atoms(
            content: content,
            dimensions: dimensions,
            rubyAtoms: [
              for (var i = 0; i < pairs; i++)
                ForumBodyRubyAtomPlan.textBaseline(
                  request: request(i * 2),
                  metrics: baselineMetrics[i],
                ),
            ],
          )
        : ForumBodyInlinePageContent(
            content: content,
            dimensions: dimensions,
            rubyGroups: [
              for (var i = 0; i < pairs; i++)
                ForumBodyRubyPairRequest(
                  base: request(i * 2),
                  annotation: request(i * 2 + 1),
                ),
            ],
          );
  }
  final ForumBodyParagraphCache cache;
  late final List<ForumBodyParagraphContent> contexts;
  late final ForumBodyInlineSpanContent content;
  late final ForumBodyInlinePageContent input;
  late final ForumBodyTextPageSnapshot snapshot;
  List<ForumBodyPreparedTextFragment>? delivered;
  int transfers = 0;
  int retirements = 0;
  final _preparations = <ForumBodyTextPagePreparation>[];
  ForumBodyTextPagePreparation open(
    int pageIndex, {
    void Function()? ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final prepare = createForumBodyTextPagePreparation(
      cache: cache,
      snapshot: snapshot,
      pageIndex: pageIndex,
      inputs: [input],
      textScaler: textScaler,
      ensureOwner: ensureOwner ?? () {},
      onTransfer: (_, fragments) {
        transfers++;
        delivered = fragments;
      },
      onRetire: (_) {
        retirements++;
      },
    );
    _preparations.add(prepare);
    return prepare;
  }

  List<ForumBodyTextPagePreparationStep> finish(
    ForumBodyTextPagePreparation prepare, {
    int maxParts = 32,
  }) {
    final steps = <ForumBodyTextPagePreparationStep>[];
    while (!prepare.isReady) {
      if (steps.length > 1000) throw StateError('Test preparation stalled');
      steps.add(prepare.advance(maxFragments: 1, maxParts: maxParts));
    }
    return steps;
  }

  void close() {
    for (final prepare in _preparations) {
      prepare.close();
    }
    for (final fragment
        in delivered ?? const <ForumBodyPreparedTextFragment>[]) {
      fragment.close();
    }
    cache.close();
  }
}
