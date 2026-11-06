import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/ruby_tree_emphasis_scene_fixture.dart';
import 'test_support/ruby_emphasis_page_fixture.dart';

const _simple = '<ruby style="text-emphasis:circle">AB<rt>x</rt></ruby>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

void _close(List<ForumBodyPreparedTextFragment> fragments) {
  for (final fragment in fragments) {
    fragment.close();
  }
}

void _paint(ForumBodyInlineParagraphView view) {
  final recorder = ui.PictureRecorder();
  try {
    view.paint(Canvas(recorder), const Offset(7.3, 8.7));
  } finally {
    recorder.endRecording().dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final (index, html) in [
        rubyTreeEmphasisSceneNested,
        rubyTreeEmphasisSceneMixed,
        rubyTreeEmphasisSceneSegment,
        '<ruby style="text-emphasis:circle">.<rt>x</rt></ruby>',
      ].indexed) {
        test(
          'real page delivery owns complete tree fixture=$index $direction $scaler',
          () {
            final f = RubyEmphasisPageFixture(
              html: html,
              direction: direction,
              scaler: scaler,
            );
            addTearDown(f.close);
            final job = f.open();
            expect(f.cache.activeLeases, 0);
            final result = f.finish(job, quantum: index + 1);
            job.close();
            try {
              final expected = f.input.nativeHandleCountFor(
                f.snapshot.single.fragments.single,
              );
              expect(job.expectedNativeLeaseCount, expected);
              expect(f.cache.activeLeases, expected);
              expect(result.expand((p) => p.nativeLeases).length, expected);
              expect(f.transfers, 1);
              validateForumBodyPreparedTextPageBinding(
                snapshot: f.snapshot,
                pageIndex: 0,
                layoutId: f.snapshot.layoutId,
                fragments: result,
              );
              final view =
                  (result.single as ForumBodyPreparedInlineFragment).view;
              final before = (
                f.cache.layoutBuildCount,
                f.cache.pictureBuildCount,
              );
              _paint(view);
              final page = f.snapshot.single.fragments.single;
              for (final box in result.single.glyphBoxes(
                page.coverageStartUtf16,
                page.coverageEndUtf16,
              )) {
                final r = box.toRect();
                expect(r.left, greaterThanOrEqualTo(-1e-4));
                expect(r.top, greaterThanOrEqualTo(-1e-4));
                expect(r.right, lessThanOrEqualTo(view.width + 1e-4));
                expect(r.bottom, lessThanOrEqualTo(view.height + 1e-4));
              }
              for (final atom
                  in f.input.rubyAtoms
                      .whereType<ForumBodyRubyTreeEmphasisAtomPlan>()) {
                for (final source in atom.request.sources.where(
                  (s) => !s.content.isSourceFree,
                )) {
                  expect(
                    view.content.contexts.any(
                      (w) => identical(w.content, source.content),
                    ),
                    isTrue,
                  );
                }
              }
              expect((
                f.cache.layoutBuildCount,
                f.cache.pictureBuildCount,
              ), before);
              if (index == 3) expect(f.cache.pictureBuildCount, 0);
            } finally {
              _close(result);
            }
            expect(f.cache.activeLeases, 0);
          },
        );
      }
    }
  }
  test(
    'initial aggregate probe includes marker fonts and one actual scene before parent acquisition',
    () {
      final f = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      final job = f.open();
      var inspected = 0;
      while (f.cache.layoutBuildCount == 0) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        inspected += step.partsInspected;
        expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(1));
        expect(step.picturesBuilt, 0);
        expect(inspected, lessThan(100));
      }
      expect(
        inspected,
        greaterThanOrEqualTo(
          f.nativeCosts.map((e) => e.identity).toSet().length,
        ),
      );
      final result = f.finish(job);
      _close(result);
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'complete atom prefix rejects an impossible page without native work',
    () {
      final f = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      final entries = f.nativeCosts.map((e) => e.identity).toSet().length;
      final small = ForumBodyParagraphCache(
        maxEntries: entries - 1,
        maxEstimatedBytes: 1 << 26,
      );
      final job = f.open(targetCache: small);
      try {
        expect(
          () => f.finish(job),
          throwsA(
            isA<ForumBodyTextPagePreparationException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyTextPagePreparationFailure.intrinsicBudget,
            ),
          ),
        );
        expect(
          (small.layoutBuildCount, small.pictureBuildCount, small.activeLeases),
          (0, 0, 0),
        );
      } finally {
        job.close();
        small.close();
      }
    },
  );
  test(
    'composer ledger distinguishes final handles from temporary fonts and scene keys',
    () {
      final f = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      final entries = f.nativeCosts.map((e) => e.identity).toSet().length,
          handles = f.input.nativeHandleCountFor(
            f.snapshot.single.fragments.single,
          );
      expect(entries, greaterThan(handles));
      expect(
        () => RubyEmphasisPageFixture(
          html: _simple,
          maxNativeEntries: entries - 1,
        ),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.nativeEntryLimit,
          ),
        ),
      );
      final exact = RubyEmphasisPageFixture(
        html: _simple,
        maxNativeEntries: entries,
        maxNativeHandles: handles,
      );
      addTearDown(exact.close);
      expect(exact.snapshot.isComplete, isTrue);
      expect(exact.snapshot, hasLength(1));
    },
  );
  test(
    'external pin retains the current complete tree preparation and release resumes it',
    () {
      final f = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      final entries = f.nativeCosts.map((e) => e.identity).toSet().length;
      final cache = ForumBodyParagraphCache(
        maxEntries: entries,
        maxEstimatedBytes: 1 << 26,
      );
      final first = f.input.content;
      final pin = cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: first.identity,
          fontRevision: first.fontRevision,
          styleRevision: first.styleRevision,
          style: ForumBodyResolvedStyle(
            textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 53),
            role: first.style.role,
            textAlign: TextAlign.start,
            textDirection: f.direction,
          ),
        ),
        width: 300,
      );
      final job = f.open(targetCache: cache);
      try {
        for (var n = 0; !job.waitingForLayoutBudget; n++) {
          expect(n, lessThan(30000));
          job.advance(maxFragments: 1, maxParts: 1);
        }
        final before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        );
        final step = job.advance(maxFragments: 1, maxParts: 32);
        expect(step.waitingForLayoutBudget, isTrue);
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        ), before);
        pin.release();
        final result = f.finish(job);
        _close(result);
        expect(cache.activeLeases, 0);
      } finally {
        job.close();
        pin.release();
        cache.close();
      }
    },
  );
  test(
    'cached-only page miss resumes and complete warm page rebuilds nothing',
    () {
      final f = RubyEmphasisPageFixture(html: rubyTreeEmphasisSceneMixed);
      addTearDown(f.close);
      final job = f.open();
      for (var n = 0; !job.cacheMiss; n++) {
        expect(n, lessThan(30000));
        expect(job.tryPrepareCached(maxParts: 1), isFalse);
        expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), (0, 0));
      }
      _close(f.finish(job));
      final counts = (f.cache.layoutBuildCount, f.cache.pictureBuildCount),
          warm = f.open();
      for (var n = 0; !warm.isReady; n++) {
        expect(n, lessThan(30000));
        warm.tryPrepareCached(maxParts: 7);
        expect(warm.cacheMiss, isFalse);
      }
      final result = warm.takeFragments();
      try {
        _paint((result.single as ForumBodyPreparedInlineFragment).view);
      } finally {
        _close(result);
      }
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), counts);
    },
  );
  test('only actual visible trees are acquired on each physical page', () {
    final f = RubyEmphasisPageFixture(
      html: '$rubyTreeEmphasisSceneNested<br>$rubyTreeEmphasisSceneMixed',
      height: 65,
    );
    addTearDown(f.close);
    expect(f.snapshot.length, greaterThan(1));
    for (var index = 0; index < f.snapshot.length; index++) {
      final job = f.open(page: index), result = f.finish(job);
      try {
        final visible = f.input.visibleAtoms(
          f.snapshot[index].fragments.single,
        );
        final expected =
            1 +
            visible.fold<int>(
              0,
              (n, i) => n + f.input.rubyAtoms[i].nativeHandleCount,
            );
        expect(f.cache.activeLeases, expected);
        expect(
          (result.single as ForumBodyPreparedInlineFragment).view.atomIndices,
          visible,
        );
        validateForumBodyPreparedTextPageBinding(
          snapshot: f.snapshot,
          pageIndex: index,
          layoutId: f.snapshot.layoutId,
          fragments: result,
        );
      } finally {
        _close(result);
      }
      expect(f.cache.activeLeases, 0);
    }
  });
  test(
    'every page preparation boundary plus ready publication closes all actual resources',
    () {
      final f = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      final count = f.open();
      var steps = 0;
      while (!count.isReady) {
        count.advance(maxFragments: 1, maxParts: 1);
        steps++;
        expect(steps, lessThan(30000));
      }
      count.close();
      for (var boundary = 0; boundary <= steps; boundary++) {
        final job = f.open();
        for (var n = 0; n < boundary && !job.isReady; n++) {
          job.advance(maxFragments: 1, maxParts: 1);
        }
        job.close();
        expect(f.cache.activeLeases, 0, reason: 'boundary=$boundary');
      }
    },
  );
  test(
    'original and projected contexts cannot be substituted by equal foreign plans',
    () {
      final f = RubyEmphasisPageFixture(html: _simple),
          foreign = RubyEmphasisPageFixture(html: _simple);
      addTearDown(f.close);
      addTearDown(foreign.close);
      final atom =
              f.input.rubyAtoms.single as ForumBodyRubyTreeEmphasisAtomPlan,
          other =
              foreign.input.rubyAtoms.single
                  as ForumBodyRubyTreeEmphasisAtomPlan;
      expect(
        () => ForumBodyRubyAtomPlan.emphasisTree(
          request: atom.request,
          format: other.format,
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyInlinePageContent.atoms(
          content: f.input.content,
          dimensions: f.input.dimensions,
          rubyAtoms: [other],
          rootFonts: foreign.input.rootFonts,
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(f.input.retainedTextCodeUnits, f.input.textCodeUnits);
      expect(f.input.retainedRuns, greaterThan(f.input.runCount));
      expect(
        (
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        ),
        (0, 0, 0),
      );
    },
  );
  test('delivered page uses reader owner after both preparations close', () {
    final f = RubyEmphasisPageFixture(html: rubyTreeEmphasisSceneMixed);
    addTearDown(f.close);
    final job = f.open(), result = f.finish(job);
    job.close();
    final view = (result.single as ForumBodyPreparedInlineFragment).view;
    try {
      _paint(view);
      f.active = false;
      expect(() => view.backgroundSurfaces, throwsStateError);
      expect(() => view.sourceAt(Offset.zero), throwsStateError);
      expect(() => result.single.glyphBoxes(0, 1), throwsStateError);
    } finally {
      _close(result);
    }
    expect(f.cache.activeLeases, 0);
  });
  for (final direction in TextDirection.values) {
    testWidgets('actual page Surface paints and routes marker tap $direction', (
      tester,
    ) async {
      final f = RubyEmphasisPageFixture(
        html: _simple,
        direction: direction,
        scaler: const _Curve(),
      );
      addTearDown(f.close);
      final job = f.open(), fragments = f.finish(job);
      final view = (fragments.single as ForumBodyPreparedInlineFragment).view,
          parent = fragments.single.nativeLeases
              .whereType<ForumBodyInlineParagraphLease>()
              .first,
          atom = f.input.rubyAtoms.single as ForumBodyRubyTreeEmphasisAtomPlan,
          marker = atom.format.placement.marks.first;
      final local =
          parent.layout.atomBoxes.single.toRect().topLeft -
          Offset(0, parent.layout.lines[view.startLine].top) +
          atom.format.frame.childOffset +
          marker.fontBounds.center;
      final expected = view.sourceAt(local);
      final taps = <int>[];
      final counts = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: f.width,
                height: f.height,
                child: ForumBodyTextPageSurface.prepared(
                  snapshot: f.snapshot,
                  pageIndex: 0,
                  layoutId: f.snapshot.layoutId,
                  fragments: fragments,
                  onSourceTap: (fragment, position) {
                    expect(fragment, same(f.snapshot.single.fragments.single));
                    expect(position.isExact, isFalse);
                    taps.add(position.sourceRune);
                  },
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final at =
            tester.getTopLeft(find.byType(ForumBodyTextPageSurface)) + local;
        await tester.tapAt(at);
        await tester.pump();
        expect(taps, [expected.sourceRune]);
        expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), counts);
        await tester.pumpWidget(const SizedBox());
      } finally {
        _close(fragments);
      }
      expect(f.cache.activeLeases, 0);
    });
  }
}
