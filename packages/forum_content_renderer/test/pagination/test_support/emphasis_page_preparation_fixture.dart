import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

class EmphasisPagePreparationFixture {
  EmphasisPagePreparationFixture({
    List<String> bodies = const ['AAAA'],
    Set<int>? emphasisIndices,
    double width = 140,
    double height = 200,
    TextDirection direction = TextDirection.ltr,
    this.scaler = TextScaler.noScaling,
    int entries = 32,
    int bytes = 1 << 25,
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: bytes,
    );
    addTearDown(close);
    final doc = const ForumBodyParser().parse(
      html: [
        for (var n = 0; n < bodies.length; n++)
          '<p style="white-space:pre-wrap;line-height:.4;'
              'text-emphasis:${emphasisIndices == null || emphasisIndices.contains(n) ? "'X' red" : 'none'}">${bodies[n]}</p>',
      ].join(),
      sourceId: 'emphasis-page-fixture',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        textDirection: direction,
        fontRevision: 'emphasis-page-ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final measured = ForumBodyParagraphCache(
          maxEntries: 64,
          maxEstimatedBytes: 1 << 26,
        ),
        composer = ForumBodyTextPageComposer(
          identity: doc.identity,
          layoutId: 'emphasis-page-layout',
          width: width,
          height: height,
          maxPages: 100,
          maxFragments: 1000,
        );
    final content = <ForumBodyTextPageContent>[];
    try {
      for (var n = 0; n < bodies.length; n++) {
        final original = const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: styles,
          path: '$n',
        );
        if (emphasisIndices == null || emphasisIndices.contains(n)) {
          final measure = ForumBodyEmphasisParagraphPreparation(
            content: original,
            cache: measured,
            ensureOwner: guard,
            width: width,
            textScaler: scaler,
          );
          while (!measure.isReady) {
            measure.advance(maxParts: 32);
          }
          final paragraph = measure.takeMetrics(),
              costs = ForumBodyEmphasisParagraphNativeEntriesPreparation(
                paragraph: paragraph,
                cache: measured,
                ensureOwner: guard,
              );
          while (!costs.isReady) {
            costs.advance(maxParts: 32);
          }
          composer.appendEmphasis(
            entries: costs.take(),
            ensureOwner: guard,
            paragraphIndex: n,
            left: 0,
            spaceBefore: 0,
            spaceAtPageStart: 0,
          );
          content.add(ForumBodyTextPageContent.emphasis(paragraph));
        } else {
          composer.append(
            lease: measured.acquire(
              content: original,
              width: width,
              textScaler: scaler,
            ),
            paragraphIndex: n,
            left: 0,
            spaceBefore: 0,
            spaceAtPageStart: 0,
          );
          content.add(ForumBodyTextPageContent.paragraph(original));
        }
        while (!composer.needsInput) {
          composer.advance(maxLines: 1);
        }
      }
      composer.finish();
      snapshot = composer.snapshot;
      inputs = List.unmodifiable(content);
    } finally {
      composer.close();
      measured.close();
    }
  }
  final TextScaler scaler;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSnapshot snapshot;
  late final List<ForumBodyTextPageContent> inputs;
  final _jobs = <ForumBodyTextPagePreparation>{};
  final issued = <ForumBodyPreparedTextFragment>{};
  bool ownerActive = true;
  int retirements = 0;
  void guard() {
    if (!ownerActive || cache.isClosed) throw StateError('Reader retired');
  }

  ForumBodyTextPagePreparation open({
    int page = 0,
    TextScaler? textScaler,
    void Function(
      ForumBodyTextPagePreparation,
      List<ForumBodyPreparedTextFragment>,
    )?
    transfer,
  }) {
    final job = createForumBodyTextPagePreparation(
      cache: cache,
      snapshot: snapshot,
      pageIndex: page,
      inputs: [
        for (final f in snapshot[page].fragments) inputs[f.paragraphIndex],
      ],
      textScaler: textScaler ?? scaler,
      ensureOwner: guard,
      onTransfer: (job, fragments) {
        _jobs.remove(job);
        issued.addAll(fragments);
        transfer?.call(job, fragments);
      },
      onRetire: (job) {
        _jobs.remove(job);
        retirements++;
      },
    );
    _jobs.add(job);
    return job;
  }

  void finish(ForumBodyTextPagePreparation job, {int maxParts = 1}) {
    for (var n = 0; !job.isReady && n < 200000; n++) {
      final step = job.advance(maxFragments: 1, maxParts: maxParts);
      expect(
        step.partsPrepared + step.partsInspected,
        lessThanOrEqualTo(maxParts),
      );
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.fragmentsPrepared, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
    }
    expect(job.isReady, isTrue);
  }

  ForumBodyEmphasisFragmentInput sceneInput(ForumBodyTextPageFragment f) {
    final content = inputs[f.paragraphIndex] as ForumBodyEmphasisPageContent,
        job = content.openFragmentInput(fragment: f, ensureOwner: guard);
    while (!job.isReady) {
      job.advance(maxParts: 32);
    }
    return job.takeInput();
  }

  int estimatedPageReservationBytes(int page) {
    final fonts = <Object, int>{}, scenes = <ForumBodyTextPictureInput>{};
    final probe = cache.createBudgetProbe(captureInputEstimates: true);
    try {
      for (final f in snapshot[page].fragments) {
        final content = inputs[f.paragraphIndex];
        for (final slot in content.nativeFootprintFor(f)) {
          slot.request.includeBudget(
            probe,
            width: slot.width,
            textScaler: scaler,
            minimumLineCount: slot.minimumLineCount,
          );
        }
        if (content is ForumBodyEmphasisPageContent) {
          scenes.add(sceneInput(f).pictureInput);
        }
      }
      for (final cost in probe.snapshotNativeEstimates()) {
        fonts[cost.identity] = cost.estimatedBytes;
      }
    } finally {
      probe.close();
    }
    return fonts.values.fold<int>(0, (sum, b) => sum + b) +
        scenes.fold<int>(0, (sum, s) => sum + s.estimatedBytes);
  }

  void close() {
    ownerActive = false;
    for (final job in _jobs.toList()) {
      job.close();
    }
    _jobs.clear();
    for (final f in issued) {
      f.close();
    }
    issued.clear();
    cache.close();
  }
}
