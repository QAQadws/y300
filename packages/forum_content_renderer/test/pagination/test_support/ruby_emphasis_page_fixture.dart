import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_inline_native_entries.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

/// Actual parser/flow, original windows, complete format, native parent and
/// composer ledger. Planning owns a separate cache; visible preparation starts
/// cold and must bind each source/resource rather than borrowing test handles.
final class RubyEmphasisPageFixture {
  RubyEmphasisPageFixture({
    required String html,
    this.direction = TextDirection.ltr,
    this.scaler = TextScaler.noScaling,
    this.width = 300,
    this.height = 240,
    int entries = 64,
    int? maxNativeEntries,
    int? maxNativeHandles,
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 26,
    );
    final planning = ForumBodyParagraphCache(
      maxEntries: 512,
      maxEstimatedBytes: 1 << 26,
    );
    final doc = const ForumBodyParser().parse(
      html: '<p>$html</p>',
      sourceId: 'ruby-emphasis-page',
      conversionIdentity: 'none',
    );
    final flow = ForumBodyTextFlowCursor(
      document: doc,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        fontRevision: 'ruby-page-ahem',
        linkColor: const Color(0xff0000ff),
        textDirection: direction,
      ),
    );
    late ForumBodyInlineFlowContent content;
    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        if (flow.current case ForumBodyTextFlowInline(content: final value)) {
          content = value;
          break;
        }
      }
    } finally {
      flow.close();
    }
    final trees =
        Map<ForumBodyRubyGroupContent, ForumBodyRubyTreeInput>.identity();
    final atoms = <ForumBodyRubyAtomPlan>[];
    final dimensions = <PlaceholderDimensions>[];
    final roots = <int, ForumBodyRubyRootFontBox>{};
    final composer = ForumBodyTextPageComposer(
      identity: doc.identity,
      layoutId: 'ruby-emphasis-page',
      width: width,
      height: height,
      maxPages: 100,
      maxFragments: 100,
      maxNativeEntriesPerPage: maxNativeEntries,
      maxNativeHandlesPerPage: maxNativeHandles,
    );
    ForumBodyInlineParagraphLease? parent;
    try {
      for (final part in content.parts.whereType<ForumBodyInlineFlowRuby>()) {
        final source = ForumBodyRubyGlyphTreeInputPreparation(
          group: part.group,
          maxWidth: width,
          ensureOwner: () {},
        );
        late ForumBodyRubyGlyphTreeInput glyphs;
        try {
          while (!source.isReady) {
            source.advance(maxParts: 1);
          }
          glyphs = source.takeInput();
        } finally {
          source.close();
        }
        trees[part.group] = glyphs.sourceTree;
        final measure = ForumBodyRubyGlyphTreeMetricsPreparation(
          input: glyphs,
          cache: planning,
          ensureOwner: () {},
          textScaler: scaler,
        );
        late ForumBodyRubyGlyphTreeMetrics metrics;
        try {
          while (!measure.isReady) {
            measure.advance(maxParts: 1);
          }
          metrics = measure.takeMetrics();
        } finally {
          measure.close();
        }
        final format = ForumBodyRubyTreeEmphasisFormatPreparation(
          glyphMetrics: metrics,
          cache: planning,
          ensureOwner: () {},
          expectedTextScaler: scaler,
        );
        late ForumBodyRubyTreeEmphasisPlan plan;
        try {
          while (!format.isReady) {
            format.advance(maxParts: 1);
          }
          plan = format.takePlan();
        } finally {
          format.close();
        }
        final root = ForumBodyRubyRootFontBox(
          input: glyphs.sourceTree.rootGroup.font,
          height: metrics.root.font.height,
          alphabeticBaseline: metrics.root.font.alphabeticBaseline,
        );
        roots[atoms.length] = root;
        dimensions.add(
          root
              .enclose(
                childSize: plan.frame.size,
                childBaseline: plan.frame.baseline,
              )
              .dimensions,
        );
        atoms.add(
          ForumBodyRubyAtomPlan.emphasisTree(request: glyphs, format: plan),
        );
      }
      final source = ForumBodyInlinePlanInput(content, width, trees: trees);
      input = ForumBodyInlinePageContent.atoms(
        content: source.content,
        dimensions: dimensions,
        rubyAtoms: atoms,
        rootFonts: roots,
      );
      parent = planning.acquireInline(
        content: input.content,
        width: width,
        dimensions: input.dimensions,
        textScaler: scaler,
      );
      final entries = ForumBodyInlineNativeEntriesPreparation(
        input: input,
        parent: parent,
        cache: planning,
        textScaler: scaler,
        ensureOwner: () {},
      );
      late ForumBodyInlineNativeEntries native;
      try {
        while (!entries.isReady) {
          entries.advance(maxParts: 1);
        }
        native = entries.take();
      } finally {
        entries.close();
      }
      nativeCosts = native.costsInRange(0, input.textCodeUnits).toList();
      composer.appendInline(
        lease: parent,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        nativeHandleCountInRange: input.nativeHandleCountInRange,
        nativeCostsInRange: native.costsInRange,
      );
      parent = null;
      for (var n = 0; !composer.needsInput; n++) {
        if (n > 10000) throw StateError('Page fixture composer stalled');
        composer.advance(maxLines: 1);
      }
      composer.finish();
      snapshot = composer.snapshot;
    } catch (_) {
      cache.close();
      rethrow;
    } finally {
      parent?.release();
      composer.close();
      planning.close();
    }
  }
  final TextDirection direction;
  final TextScaler scaler;
  final double width, height;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyInlinePageContent input;
  late final ForumBodyTextPageSnapshot snapshot;
  late final List<ForumBodyNativeInputCost> nativeCosts;
  bool active = true;
  int transfers = 0, retirements = 0;
  final List<ForumBodyTextPagePreparation> _jobs = [];
  void guard() {
    if (!active) throw StateError('Reader owner retired');
  }

  ForumBodyTextPagePreparation open({
    int page = 0,
    ForumBodyParagraphCache? targetCache,
    void Function()? owner,
    ForumBodyInlinePageContent? currentInput,
  }) {
    final job = createForumBodyTextPagePreparation(
      cache: targetCache ?? cache,
      snapshot: snapshot,
      pageIndex: page,
      inputs: [for (final _ in snapshot[page].fragments) currentInput ?? input],
      textScaler: scaler,
      ensureOwner: owner ?? guard,
      onTransfer: (_, fragments) {
        transfers++;
      },
      onRetire: (_) {
        retirements++;
      },
    );
    _jobs.add(job);
    return job;
  }

  List<ForumBodyPreparedTextFragment> finish(
    ForumBodyTextPagePreparation job, {
    int quantum = 1,
  }) {
    for (var n = 0; !job.isReady; n++) {
      if (n > 30000) throw StateError('Page fixture preparation stalled');
      final step = job.advance(maxFragments: 1, maxParts: quantum);
      if (step.layoutsBuilt + step.picturesBuilt > 1 ||
          step.partsPrepared + step.partsInspected > quantum ||
          step.waitingForLayoutBudget) {
        throw StateError('Page fixture work quantum/wait');
      }
    }
    return job.takeFragments();
  }

  void close() {
    for (final job in _jobs) {
      job.close();
    }
    cache.close();
  }
}
