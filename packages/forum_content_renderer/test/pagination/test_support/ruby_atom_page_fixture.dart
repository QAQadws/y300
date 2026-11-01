import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

import '../../inline/test_support/ruby_segment_fixture.dart';

/// Actual parser requests -> glyph-only planning -> Composer -> cold Page job.
/// Visible preparation cannot borrow any planning native lease or picture.
final class RubyAtomPageFixture {
  RubyAtomPageFixture._(
    this.input,
    this.snapshot,
    this.textScaler,
    this.source, {
    required int entries,
  }) : cache = ForumBodyParagraphCache(
         maxEntries: entries,
         maxEstimatedBytes: 1 << 24,
       );

  factory RubyAtomPageFixture.segment({
    bool dense = false,
    bool surrounding = false,
    bool individual = false,
    int entries = 4,
    TextDirection direction = TextDirection.ltr,
    double lineHeight = 1,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final source = RubySegmentFixture(
      dense: dense,
      direction: direction,
      lineHeight: lineHeight,
      textScaler: textScaler,
      prefix: surrounding ? 'P' * 50 : '',
      suffix: surrounding ? 'Q' * 50 : '',
    );
    final request = source.request(individual: individual);
    source.releaseGlyphs();
    final job = ForumBodyRubySegmentMetricsPreparation(
      cache: source.cache,
      request: request,
      ensureOwner: () {},
      textScaler: textScaler,
    );
    try {
      for (var i = 0; !job.isReady && i < 30000; i++) {
        final step = job.advance(maxParts: 7);
        if (step.formatUnitsPrepared > 7 ||
            step.layoutsBuilt > 1 ||
            step.picturesBuilt != 0 ||
            source.cache.activeLeases > 1) {
          throw StateError('Invalid glyph planning quantum');
        }
      }
      if (!job.isReady) throw StateError('Glyph planning incomplete');
      final metrics = job.takeMetrics();
      final input = ForumBodyInlinePageContent.atoms(
        content: source.inlineContent,
        dimensions: [metrics.placeholderDimensions],
        rubyAtoms: [
          ForumBodyRubyAtomPlan.segment(request: request, metrics: metrics),
        ],
      );
      return RubyAtomPageFixture.compose(
        input: input,
        planning: source.cache,
        textScaler: textScaler,
        source: source,
        entries: entries,
        width: surrounding ? 160 : 300,
        height: surrounding ? 140 : 500,
      );
    } finally {
      job.close();
      source.close();
    }
  }

  factory RubyAtomPageFixture.compose({
    required ForumBodyInlinePageContent input,
    required ForumBodyParagraphCache planning,
    int entries = 4,
    double width = 300,
    double height = 500,
    TextScaler textScaler = TextScaler.noScaling,
    RubySegmentFixture? source,
  }) {
    final composer = ForumBodyTextPageComposer(
      identity: input.identity,
      layoutId: 'atom-page',
      width: width,
      height: height,
      maxPages: 100,
      maxFragments: 100,
    );
    try {
      composer.appendInline(
        lease: planning.acquireInline(
          content: input.content,
          width: width,
          dimensions: input.dimensions,
          textScaler: textScaler,
          layoutMode: input.layoutMode,
        ),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      for (var i = 0; !composer.needsInput && i < 10000; i++) {
        composer.advance(maxLines: 1);
      }
      if (!composer.needsInput) throw StateError('Atom composition stalled');
      composer.finish();
      return RubyAtomPageFixture._(
        input,
        composer.snapshot,
        textScaler,
        source,
        entries: entries,
      );
    } finally {
      composer.close();
      planning.close();
    }
  }
  final ForumBodyInlinePageContent input;
  final ForumBodyTextPageSnapshot snapshot;
  final TextScaler textScaler;
  final RubySegmentFixture? source;
  final ForumBodyParagraphCache cache;
  final _jobs = <ForumBodyTextPagePreparation>[];
  final _fragments = <ForumBodyPreparedTextFragment>[];
  var transfers = 0;
  var retirements = 0;
  int get atomPage => snapshot.indexWhere(
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
      textScaler: textScaler,
      ensureOwner: ensureOwner ?? () {},
      onTransfer: (_, fragments) {
        transfers++;
        _fragments.addAll(fragments);
      },
      onRetire: (_) {
        retirements++;
      },
    );
    _jobs.add(job);
    return job;
  }

  void finish(ForumBodyTextPagePreparation job, {int q = 7}) {
    for (var i = 0; !job.isReady && i < 30000; i++) {
      final step = job.advance(maxFragments: 32, maxParts: q);
      if (step.partsPrepared + step.partsInspected > q ||
          step.layoutsBuilt + step.picturesBuilt > 1 ||
          step.waitingForLayoutBudget ||
          !step.madeProgress) {
        throw StateError('Unbounded or stalled atom page');
      }
    }
    if (!job.isReady) throw StateError('Atom page preparation incomplete');
  }

  void close() {
    for (final job in _jobs) {
      job.close();
    }
    for (final fragment in _fragments) {
      fragment.close();
    }
    cache.close();
    source?.close();
  }
}
