import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

import 'test_support/emphasis_page_preparation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'pure page preflight is bounded and a cold page transfers one current scene',
    () {
      final f = EmphasisPagePreparationFixture(
            bodies: ['AAAA'],
            width: 1,
            entries: 6,
          ),
          job = f.open();
      expect(job.expectedNativeLeaseCount, 2);
      var inspections = 0;
      while (f.cache.layoutBuildCount == 0) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
        inspections += step.partsInspected;
        expect(inspections, lessThan(1000));
      }
      expect(
        inspections,
        greaterThan(
          f
              .sceneInput(f.snapshot.single.fragments.single)
              .pictureInput
              .commands
              .length,
        ),
      );
      f.finish(job);
      expect(() => job.takeLeases(), throwsStateError);
      final bindings = job.takeFragments();
      expect(bindings.single, isA<ForumBodyPreparedEmphasisFragment>());
      final view = (bindings.single as ForumBodyPreparedEmphasisFragment).view;
      expect(f.cache.layoutBuildCount, 5);
      expect(f.cache.pictureBuildCount, 4);
      expect(f.cache.activeLeases, 2);
      job.close();
      expect(view.sourceAt(Offset.zero).displayUtf16, inInclusiveRange(0, 4));
      expect(bindings.single.glyphBoxes(0, 4), isNotEmpty);
      final r = ui.PictureRecorder();
      view.paint(Canvas(r), Offset.zero);
      r.endRecording().dispose();
      validateForumBodyPreparedTextPageBinding(
        snapshot: f.snapshot,
        pageIndex: 0,
        layoutId: f.snapshot.layoutId,
        fragments: bindings,
      );
      bindings.single.close();
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'cold cached-only continuation does no native work and warm views get distinct handles',
    () {
      final f = EmphasisPagePreparationFixture(width: 1, entries: 6),
          cold = f.open();
      for (var n = 0; !cold.cacheMiss && n < 10000; n++) {
        expect(cold.tryPrepareCached(maxParts: 1), isFalse);
        expect(
          f.cache.layoutBuildCount +
              f.cache.pictureBuildCount +
              f.cache.hitCount,
          0,
        );
      }
      expect(cold.cacheMiss, isTrue);
      f.finish(cold);
      final first = cold.takeFragments().single;
      final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount),
          warm = f.open();
      for (var n = 0; !warm.isReady && n < 10000; n++) {
        warm.tryPrepareCached(maxParts: 1);
        expect(warm.cacheMiss, isFalse);
      }
      expect(warm.isReady, isTrue);
      final second = warm.takeFragments().single;
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
      expect(f.cache.activeLeases, 4);
      expect(
        first.nativeLeases.toSet().intersection(second.nativeLeases.toSet()),
        isEmpty,
      );
      expect(
        first.nativeLeases.last.nativeInputIdentity,
        second.nativeLeases.last.nativeInputIdentity,
      );
      first.close();
      second.close();
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'whole-page fonts AND distinct scenes reject intrinsically before any native acquisition',
    () {
      for (final maxEntries in [6, 10]) {
        final f = EmphasisPagePreparationFixture(
              bodies: ['AAAA', 'CCCC'],
              width: 1,
              height: 1000,
              entries: maxEntries,
            ),
            job = f.open();
        expect(job.expectedNativeLeaseCount, 4);
        expect(
          () => f.finish(job),
          throwsA(isA<ForumBodyTextPagePreparationException>()),
        );
        expect(
          (
            f.cache.layoutBuildCount,
            f.cache.pictureBuildCount,
            f.cache.hitCount,
            f.cache.activeLeases,
          ),
          (0, 0, 0, 0),
        );
        expect(job.state, ForumBodyTextPagePreparationState.failed);
        expect(job.waitingForLayoutBudget, isFalse);
        expect(f.retirements, 1);
        expect(f.snapshot.single.fragments, hasLength(2));
      }
      final reference = EmphasisPagePreparationFixture(
        bodies: ['AAAA', 'CCCC'],
        width: 1,
        height: 1000,
      );
      // Stable font-table estimates are larger than cold request lower bounds.
      // Verify the configured budget admits a complete prefix but not the page.
      final bytes =
          reference.estimatedPageReservationBytes(0) -
          ForumBodyTextPictureInput.baseEstimatedPictureBytes;
      final prefix = EmphasisPagePreparationFixture(width: 1, bytes: bytes);
      final prefixJob = prefix.open();
      prefix.finish(prefixJob);
      prefixJob.takeFragments().single.close();
      final f = EmphasisPagePreparationFixture(
            bodies: ['AAAA', 'CCCC'],
            width: 1,
            height: 1000,
            bytes: bytes,
          ),
          job = f.open();
      expect(
        () => f.finish(job),
        throwsA(isA<ForumBodyTextPagePreparationException>()),
      );
      expect(f.cache.layoutBuildCount + f.cache.pictureBuildCount, 0);
    },
  );
  test(
    'exact duplicate scene keys deduplicate in actual aggregate preflight',
    () {
      final f = EmphasisPagePreparationFixture(width: 1, entries: 6),
          input = f.inputs.single as ForumBodyEmphasisPageContent,
          index = ForumBodyEmphasisParagraphNativeEntriesPreparation(
            paragraph: input.paragraph,
            cache: f.cache,
            ensureOwner: f.guard,
          );
      while (!index.isReady) {
        index.advance(maxParts: 32);
      }
      final entries = index.take(),
          composer = ForumBodyTextPageComposer(
            identity: f.snapshot.identity,
            layoutId: 'repeated-scene',
            width: 1,
            height: 1000,
            maxPages: 10,
            maxFragments: 10,
          );
      for (var n = 0; n < 2; n++) {
        composer.appendEmphasis(
          entries: entries,
          ensureOwner: f.guard,
          paragraphIndex: n,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
        );
        while (!composer.needsInput) {
          composer.advance(maxLines: 1);
        }
      }
      composer.finish();
      final snapshot = composer.snapshot;
      composer.close();
      final job = createForumBodyTextPagePreparation(
        cache: f.cache,
        snapshot: snapshot,
        pageIndex: 0,
        inputs: [input, input],
        textScaler: f.scaler,
        ensureOwner: f.guard,
        onTransfer: (_, fragments) => f.issued.addAll(fragments),
        onRetire: (_) {},
      );
      addTearDown(job.close);
      f.finish(job);
      final bindings = job.takeFragments();
      expect(bindings, hasLength(2));
      expect(f.cache.activeLeases, 4);
      expect(
        bindings[0].nativeLeases.last.nativeInputIdentity,
        bindings[1].nativeLeases.last.nativeInputIdentity,
      );
      expect(f.cache.pictureBuildCount, 4);
    },
  );
  test(
    'external pressure waits only after complete inspection and resumes the same work',
    () {
      final f = EmphasisPagePreparationFixture(width: 1, entries: 6),
          content = (f.inputs.single as ForumBodyEmphasisPageContent)
              .paragraph
              .glyphInput
              .glyphs;
      final pins = [
            for (final width in [2.0, 3.0])
              f.cache.acquire(content: content, width: width),
          ],
          job = f.open();
      for (var n = 0; !job.waitingForLayoutBudget && n < 10000; n++) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(1));
      }
      expect(job.waitingForLayoutBudget, isTrue);
      final before = (
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.activeLeases,
      );
      for (var n = 0; n < 3; n++) {
        final step = job.advance(maxFragments: 1, maxParts: 32);
        expect(step.waitingForLayoutBudget, isTrue);
        expect(step.partsPrepared + step.partsInspected, 0);
        expect((
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        ), before);
      }
      for (final pin in pins) {
        pin.release();
      }
      f.finish(job);
      job.takeFragments().single.close();
      expect(f.cache.activeLeases, 0);
    },
  );
  for (final emphasisFirst in [false, true]) {
    test(
      'ordinary and emphasis resources transfer together order=$emphasisFirst',
      () {
        final f = EmphasisPagePreparationFixture(
              bodies: emphasisFirst ? ['AAAA', 'B'] : ['B', 'AAAA'],
              emphasisIndices: {emphasisFirst ? 0 : 1},
              width: 1,
              entries: 7,
            ),
            job = f.open();
        f.finish(job);
        final bindings = job.takeFragments();
        expect(
          bindings.map((b) => b.runtimeType),
          emphasisFirst
              ? [
                  ForumBodyPreparedEmphasisFragment,
                  ForumBodyPreparedParagraphFragment,
                ]
              : [
                  ForumBodyPreparedParagraphFragment,
                  ForumBodyPreparedEmphasisFragment,
                ],
        );
        expect(f.cache.activeLeases, 3);
        job.close();
        validateForumBodyPreparedTextPageBinding(
          snapshot: f.snapshot,
          pageIndex: 0,
          layoutId: f.snapshot.layoutId,
          fragments: bindings,
        );
      },
    );
  }
  test(
    'canceling pure scene planning consumes no native resource or late transfer',
    () {
      final f = EmphasisPagePreparationFixture(width: 1), job = f.open();
      for (var n = 0; n < 12; n++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(f.cache.layoutBuildCount + f.cache.pictureBuildCount, 0);
      job.close();
      expect(job.takeFragments, throwsStateError);
      expect(() => job.advance(maxFragments: 1), throwsStateError);
      expect(f.cache.activeLeases, 0);
    },
  );
  for (final cacheRetires in [false, true]) {
    for (final picture in [1, 2, 3, 4]) {
      test(
        'recording retirement picture=$picture cache=$cacheRetires drains the full page',
        () {
          final f = EmphasisPagePreparationFixture(width: 1), job = f.open();
          final oldCreate = ui.Picture.onCreate,
              oldDispose = ui.Picture.onDispose;
          var created = 0, disposed = 0;
          ui.Picture.onCreate = (_) {
            if (++created == picture) {
              if (cacheRetires) {
                f.cache.close();
              } else {
                job.close();
              }
            }
          };
          ui.Picture.onDispose = (_) {
            disposed++;
          };
          try {
            expect(() => f.finish(job), throwsStateError);
            f.cache.close();
          } finally {
            ui.Picture.onCreate = oldCreate;
            ui.Picture.onDispose = oldDispose;
          }
          expect(created, picture);
          expect(disposed, picture);
          expect(f.cache.activeLeases, 0);
          expect(job.isReady, isFalse);
        },
      );
    }
  }
  test('transfer callback retirement cannot leak ready fragments', () {
    final f = EmphasisPagePreparationFixture(width: 1),
        job = f.open(transfer: (job, fragments) => job.close());
    f.finish(job);
    expect(job.takeFragments, throwsStateError);
    expect(f.cache.activeLeases, 0);
    expect(f.issued.every((fragment) => !fragment.isActive), isTrue);
  });
  test(
    'changed actual scaling rejects before shaping and page metadata cannot replace source identity',
    () {
      final f = EmphasisPagePreparationFixture(width: 1),
          changed = f.open(textScaler: TextScaler.linear(2));
      expect(
        () => f.finish(changed),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(f.cache.layoutBuildCount + f.cache.pictureBuildCount, 0);
      final valid = f.open();
      f.finish(valid);
      final bindings = valid.takeFragments();
      final other = EmphasisPagePreparationFixture(bodies: ['CCCC'], width: 1);
      expect(
        () => validateForumBodyPreparedTextPageBinding(
          snapshot: other.snapshot,
          pageIndex: 0,
          layoutId: other.snapshot.layoutId,
          fragments: bindings,
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(bindings.single.isActive, isTrue);
      final content = f.inputs.single as ForumBodyEmphasisPageContent;
      expect(
        content.retainedTextCodeUnits,
        content.paragraph.retainedTextCodeUnits,
      );
      expect(content.retainedTextCodeUnits, greaterThan(content.textCodeUnits));
    },
  );
  test(
    'middle-page delivery retains whole-paragraph coordinates and exact current row geometry',
    () {
      final f = EmphasisPagePreparationFixture(bodies: ['A\nB\nC'], height: 40),
          job = f.open(page: 1);
      expect(f.snapshot.length, 3);
      f.finish(job);
      final binding =
              job.takeFragments().single as ForumBodyPreparedEmphasisFragment,
          fragment = f.snapshot[1].fragments.single;
      job.close();
      expect(binding.projection.text, 'A\nB\nC');
      expect(binding.view.coverageStartUtf16, 2);
      expect(binding.view.coverageEndUtf16, 4);
      expect(binding.lines.single.coverageStartUtf16, 2);
      final boxes = binding.view.selectionBoxes(2, 3);
      expect(boxes, hasLength(1));
      expect(
        binding.view.sourceAt(boxes.single.toRect().center).displayUtf16,
        inInclusiveRange(2, 3),
      );
      expect(binding.view.height, fragment.height);
      validateForumBodyPreparedTextPageBinding(
        snapshot: f.snapshot,
        pageIndex: 1,
        layoutId: f.snapshot.layoutId,
        fragments: [binding],
      );
      expect(binding.glyphBoxes(0, 2), isEmpty);
      expect(binding.glyphBoxes(2, 3), isNotEmpty);
    },
  );
  test(
    'real terminal page owns source and empty scene without claiming glyph coverage',
    () {
      final measured = EmphasisPagePreparationFixture(bodies: ['A\n']);
      final paragraph =
          (measured.inputs.single as ForumBodyEmphasisPageContent).paragraph;
      final height = paragraph.groups.fold<double>(
        0,
        (height, group) => height > group.height ? height : group.height,
      );
      final f = EmphasisPagePreparationFixture(
            bodies: ['A\n'],
            height: height,
            entries: 5,
          ),
          job = f.open(page: 1);
      expect(f.snapshot.length, 2);
      f.finish(job);
      final binding =
          job.takeFragments().single as ForumBodyPreparedEmphasisFragment;
      expect(binding.view.coverageStartUtf16, 2);
      expect(binding.view.coverageEndUtf16, 2);
      expect(f.snapshot[1].fragments.single.sourceHint, isNull);
      expect(binding.glyphBoxes(0, 2), isEmpty);
      expect(binding.view.sourceAt(Offset.zero).displayUtf16, 2);
      expect(f.cache.activeLeases, 2);
      expect(f.cache.layoutBuildCount, 4);
      binding.close();
      expect(f.cache.activeLeases, 0);
    },
  );
}
