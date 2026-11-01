import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

import '../../inline/test_support/ruby_layer_fixture.dart';

/// Real RTC grammar, glyph-only planning and the actual composed-page job.
/// The visible cache starts cold and has no access to planning's native data.
final class LayerPagePreparationFixture {
  LayerPagePreparationFixture({
    int ranks = 100,
    bool missing = false,
    bool emptyBase = false,
    bool surroundingText = false,
    String direction = 'ltr',
    int entries = 3,
    List<ForumBodyRubySide>? sides,
  }) : cache = ForumBodyParagraphCache(
         maxEntries: entries,
         maxEstimatedBytes: 1 << 24,
       ) {
    raw = rubyLayerInput(
      prefix: surroundingText ? 'PPPPPPPPPPPP' : '',
      suffix: surroundingText ? 'QQQQQQQQQQQQ' : '',
      base: emptyBase
          ? ''
          : direction == 'rtl'
          ? 'אב'
          : 'AB',
      direction: direction,
      annotations: [
        for (var i = 0; i < ranks; i++)
          (missing && i % 17 != 0 ? '' : 'r$i', 1.0),
      ],
    );
    final glyphs = raw.parts
        .where((part) => part.projection.text.isNotEmpty)
        .toList();
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
    ForumBodyTextRequest request(ForumBodyParagraphContent part) =>
        requests[part] ?? ForumBodyTextRequest.paragraph(part);
    column = ForumBodyRubyColumnRequest.layers(
      base: request(raw.parts.first),
      annotations: [
        for (var rank = 0; rank < ranks; rank++)
          (
            request: request(raw.parts[rank + 1]),
            gap: 0.0,
            side:
                sides?[rank] ??
                (rank.isEven
                    ? ForumBodyRubySide.over
                    : ForumBodyRubySide.under),
          ),
      ],
    );
    final planning = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 24,
    );
    final composer = ForumBodyTextPageComposer(
      identity: raw.content.identity,
      layoutId: 'layer-page',
      width: 60,
      height: 130,
      maxPages: 100,
      maxFragments: 100,
    );
    final measure = ForumBodyRubyGroupPreparation.forLayerMetrics(
      cache: planning,
      base: column.base,
      annotations: column.annotations,
      ensureOwner: () {},
    );
    try {
      while (!measure.isReady) {
        measure.advance(maxParts: 7);
      }
      metrics = measure.takeMetrics();
      input = ForumBodyInlinePageContent(
        content: raw.content,
        dimensions: [metrics.placeholderDimensions],
        rubyGroups: [column],
      );
      composer.appendInline(
        lease: planning.acquireInline(
          content: raw.content,
          width: 60,
          dimensions: input.dimensions,
        ),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      for (var i = 0; !composer.needsInput && i < 1000; i++) {
        composer.advance(maxLines: 1);
      }
      if (!composer.needsInput) throw StateError('Test page planning stalled');
      composer.finish();
      snapshot = composer.snapshot;
    } finally {
      measure.close();
      composer.close();
      planning.close();
    }
  }
  final ForumBodyParagraphCache cache;
  late final RubyLayerFixture raw;
  late final ForumBodyRubyColumnRequest column;
  late final ForumBodyRubyGroupMetrics metrics;
  late final ForumBodyInlinePageContent input;
  late final ForumBodyTextPageSnapshot snapshot;
  final _jobs = <ForumBodyTextPagePreparation>[];
  final _delivered = <ForumBodyPreparedTextFragment>[];
  int transfers = 0;
  int retirements = 0;
  int get columnPage => snapshot.indexWhere(
    (page) => page.fragments.any(
      (fragment) => input.visibleAtoms(fragment).isNotEmpty,
    ),
  );

  ForumBodyTextPagePreparation open(int page, {void Function()? ensureOwner}) {
    final job = createForumBodyTextPagePreparation(
      cache: cache,
      snapshot: snapshot,
      pageIndex: page,
      inputs: [for (final _ in snapshot[page].fragments) input],
      textScaler: TextScaler.noScaling,
      ensureOwner: ensureOwner ?? () {},
      onTransfer: (_, fragments) {
        transfers++;
        _delivered.addAll(fragments);
      },
      onRetire: (_) {
        retirements++;
      },
    );
    _jobs.add(job);
    return job;
  }

  void finish(ForumBodyTextPagePreparation job) {
    for (var i = 0; !job.isReady && i < 10000; i++) {
      final step = job.advance(maxFragments: 1, maxParts: 1);
      if (step.layoutsBuilt + step.picturesBuilt > 1 ||
          step.waitingForLayoutBudget ||
          !step.madeProgress) {
        throw StateError('Unbounded or stalled page preparation');
      }
    }
    if (!job.isReady) throw StateError('Page job did not finish');
  }

  void close() {
    for (final job in _jobs) {
      job.close();
    }
    for (final fragment in _delivered) {
      fragment.close();
    }
    cache.close();
  }
}
