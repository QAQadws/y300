import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';

import '../inline/test_support/ruby_soft_space_row_fixture.dart';
import 'test_support/ruby_atom_page_fixture.dart';

void _drive(ForumBodyRubyRowAlignment work, int q) {
  for (var i = 0; !work.isComplete && !work.needsRows && i < 30000; i++) {
    expect(work.advance(maxParts: q), inInclusiveRange(1, q));
  }
}

ForumBodyInlinePageContent _plan(
  RubySoftSpaceRowFixture f,
  double width, {
  bool bands = false,
}) {
  final requests =
      Map<ForumBodyParagraphContent, ForumBodyTextRequest>.identity();
  if (bands) {
    // Bands follow the actual original source axis; parent display is column-
    // major and explicitly retains a different source permutation.
    final contexts = f.content.contexts.map((c) => c.content).toList()
      ..sort(
        (a, b) => a.projection
            .sourceAtUtf16(0)
            .sourceRune
            .compareTo(b.projection.sourceAtUtf16(0).sourceRune),
      );
    for (var start = 0; start < contexts.length; start += 64) {
      final band = ForumBodyTextBandContent(
        contexts: contexts.sublist(
          start,
          (start + 64).clamp(0, contexts.length),
        ),
      );
      for (var i = 0; i < band.contexts.length; i++) {
        requests[band.contexts[i]] = ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: i,
        );
      }
    }
  }
  ForumBodyTextRequest map(ForumBodyTextRequest r) => requests[r.content] ?? r;
  final space = f.softSpace.mapRequests(map);
  final columns = [
    for (final c in f.columns)
      ForumBodyRubyColumnRequest.layers(
        base: map(c.base),
        annotations: [
          for (final a in c.annotations)
            (request: map(a.request), gap: a.gap, side: a.side),
        ],
      ),
  ];
  final metrics = <ForumBodyRubyAtomMetrics>[];
  for (final c in columns) {
    final job = ForumBodyRubyGroupPreparation.forLayerMetrics(
      cache: f.cache,
      base: c.base,
      annotations: c.annotations,
      ensureOwner: () {},
      textScaler: f.textScaler,
    );
    while (!job.isReady) {
      job.advance(maxParts: 7);
    }
    metrics.add(ForumBodyRubyAtomMetrics.column(job.takeMetrics()));
    job.close();
  }
  final spaceJob = ForumBodyRubySoftSpacePreparation.forMetrics(
    cache: f.cache,
    request: space,
    ensureOwner: () {},
    textScaler: f.textScaler,
  );
  while (!spaceJob.isReady) {
    spaceJob.advance(maxParts: 7);
  }
  metrics.insert(1, ForumBodyRubyAtomMetrics.softSpace(spaceJob.takeMetrics()));
  spaceJob.close();
  final work = ForumBodyRubyRowAlignment.atoms(
    atoms: metrics,
    levelIds: [0, 0, 0],
    atomOffsets: f.offsets,
  );
  _drive(work, 7);
  final probe = f.parent(width, work.provisionalDimensions);
  work.attachRows(
    probe.layout.lines,
    trimmedAtomIndices: probe.layout.trimmedAtomIndices.toSet(),
  );
  _drive(work, 7);
  probe.releaseProvisional();
  final parent = f.parent(width, work.dimensions);
  try {
    final trimmed = parent.layout.trimmedAtomIndices.toSet();
    while (!work.isVerified) {
      work.verifyRows(
        parent.layout.lines,
        maxParts: 7,
        trimmedAtomIndices: trimmed,
      );
    }
    return ForumBodyInlinePageContent.atoms(
      content: f.content,
      dimensions: work.dimensions,
      trimmedAtomIndices: trimmed,
      rubyAtoms: [
        ForumBodyRubyAtomPlan.column(
          request: columns[0],
          level: work.targets[0],
        ),
        ForumBodyRubyAtomPlan.softSpace(
          request: space,
          metrics: (work.results[1] as ForumBodyRubySpaceMetrics).value,
        ),
        ForumBodyRubyAtomPlan.column(
          request: columns[1],
          level: work.targets[2],
        ),
      ],
    );
  } finally {
    parent.release();
  }
}

Future<List<int>> _pixels(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(3));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(300, 300);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final q in [1, 7, 32]) {
    for (final direction in TextDirection.values) {
      for (final trimmed in [false, true]) {
        test(
          'cold Page prepares actual source gaps and excludes native trims q=$q $direction trimmed=$trimmed',
          () {
            final f = RubySoftSpaceRowFixture(
              direction: direction,
              baseGap: true,
              ranks: 3,
              gapSize: 40,
              textScaler: const TextScaler.linear(1.27),
            );
            addTearDown(f.close);
            final width = trimmed ? f.columnMetrics.first.size.width : 200.0;
            final input = _plan(f, width);
            expect(input.trimmedAtomIndices, trimmed ? {1} : isEmpty);
            final page = RubyAtomPageFixture.compose(
              input: input,
              planning: f.cache,
              width: width,
              height: 500,
              textScaler: f.textScaler,
              entries: 20,
            );
            addTearDown(page.close);
            final job = page.open(0);
            expect(job.expectedNativeLeaseCount, trimmed ? 9 : 13);
            page.finish(job, q: q);
            final fragment =
                job.takeFragments().single as ForumBodyPreparedInlineFragment;
            expect(fragment.view.atomIndices, trimmed ? [0, 2] : [0, 1, 2]);
            expect(fragment.nativeLeases.length, job.expectedNativeLeaseCount);
            for (final context in input.content.contexts) {
              final gap = input.rubyAtoms[1].nativeRequests.any(
                (r) => identical(r.content, context.content),
              );
              final boxes = fragment.view.selectionBoxes(
                context.startUtf16,
                context.endUtf16,
              );
              if (trimmed && gap) {
                expect(boxes, isEmpty);
                continue;
              }
              expect(boxes, isNotEmpty);
              final hit = fragment.view.sourceAt(boxes.first.toRect().center);
              expect(
                hit.sourceRune,
                inInclusiveRange(
                  context.content.projection.sourceAtUtf16(0).sourceRune,
                  context.content.projection
                      .sourceAtUtf16(context.content.projection.text.length)
                      .sourceRune,
                ),
              );
            }
            fragment.close();
            expect(page.cache.activeLeases, 0);
            final builds = (
              page.cache.layoutBuildCount,
              page.cache.pictureBuildCount,
            );
            final warm = page.open(0);
            for (var i = 0; !warm.isReady && i < 30000; i++) {
              warm.tryPrepareCached(maxParts: q);
            }
            expect(warm.isReady, isTrue);
            expect((
              page.cache.layoutBuildCount,
              page.cache.pictureBuildCount,
            ), builds);
            for (final f in warm.takeFragments()) {
              f.close();
            }
            page.close();
            expect(page.cache.activeLeases, 0);
            expect(page.cache.estimatedRetainedBytes, 0);
          },
        );
      }
    }
  }

  for (final q in [1, 7, 32]) {
    test(
      'dense actual gap members share real bands through cold Page q=$q',
      () {
        final f = RubySoftSpaceRowFixture(ranks: 80, gapSize: 1);
        addTearDown(f.close);
        final input = _plan(f, 41, bands: true);
        final page = RubyAtomPageFixture.compose(
          input: input,
          planning: f.cache,
          width: 41,
          height: 500,
          entries: 5,
        );
        addTearDown(page.close);
        final job = page.open(0);
        page.finish(job, q: q);
        final view =
            (job.takeFragments().single as ForumBodyPreparedInlineFragment);
        expect(view.view.atomIndices, [0, 1, 2]);
        expect(view.nativeLeases.length, 243);
        expect(page.cache.layoutBuildCount, 5);
        expect(page.cache.pictureBuildCount, 242);
        view.close();
        expect(page.cache.activeLeases, 0);
      },
    );
  }

  test(
    'incorrect pure trim snapshots are rejected against actual native parent before child preparation',
    () {
      final f = RubySoftSpaceRowFixture(gapSize: 300);
      addTearDown(f.close);
      final good = _plan(f, 20);
      final bad = ForumBodyInlinePageContent.atoms(
        content: good.content,
        dimensions: good.dimensions,
        rubyAtoms: good.rubyAtoms,
      );
      final page = RubyAtomPageFixture.compose(
        input: bad,
        planning: f.cache,
        width: 20,
        height: 500,
        entries: 10,
      );
      addTearDown(page.close);
      final job = page.open(0);
      expect(
        () => page.finish(job, q: 1),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(page.cache.activeLeases, 0);
      expect(page.cache.pictureBuildCount, 0);
      expect(() => job.takeFragments(), throwsStateError);
    },
  );

  for (final direction in TextDirection.values) {
    test(
      'real prepared mixed-gap view matches independent native glyph pixels DPR3 $direction',
      () async {
        final f = RubySoftSpaceRowFixture(
          direction: direction,
          baseGap: true,
          gapSize: 40,
        );
        addTearDown(f.close);
        final input = _plan(f, 80);
        final control = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(control.close);
        final leases = [
          for (final col in f.columns) ...[
            col.base.acquire(
              control,
              width: 2000,
              textScaler: TextScaler.noScaling,
              cachedOnly: false,
            )!,
            col.annotations.single.request.acquire(
              control,
              width: 2000,
              textScaler: TextScaler.noScaling,
              cachedOnly: false,
            )!,
          ],
        ];
        final page = RubyAtomPageFixture.compose(
          input: input,
          planning: f.cache,
          width: 80,
          height: 100,
          entries: 8,
        );
        addTearDown(page.close);
        final job = page.open(0);
        page.finish(job);
        final fragment =
            job.takeFragments().single as ForumBodyPreparedInlineFragment;
        try {
          final actual = await _pixels(
            (c) => fragment.view.paint(c, Offset.zero),
          );
          // Independent Ahem control: original base20, RT10, actual base/RT gap
          // fonts40. Common base envelope40 +annotation40, base baseline72.
          final expected = await _pixels((c) {
            for (var col = 0; col < 2; col++) {
              final x = (direction == TextDirection.ltr ? col : 1 - col) * 60.0;
              leases[col * 2].layout.paint(c, Offset(x, 56));
              leases[col * 2 + 1].layout.paint(c, Offset(x + 5, 24));
            }
          });
          var differences = 0;
          for (var i = 0; i < actual.length; i++) {
            if (actual[i] != expected[i]) differences++;
          }
          expect(
            differences,
            0,
            reason:
                'Full prepared-page RGBA against original font/role control',
          );
        } finally {
          fragment.close();
          for (final lease in leases) {
            lease.release();
          }
        }
      },
    );
  }

  test(
    'two real pages reserve only their visible column, never a trimmed gap',
    () {
      final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
      addTearDown(f.close);
      final input = _plan(f, 20);
      final page = RubyAtomPageFixture.compose(
        input: input,
        planning: f.cache,
        width: 20,
        height: f.columnMetrics.first.size.height,
        entries: 10,
      );
      addTearDown(page.close);
      expect(page.snapshot.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(input.visibleAtoms(page.snapshot[i].fragments.single), [i * 2]);
        final job = page.open(i);
        expect(job.expectedNativeLeaseCount, 5);
        page.finish(job, q: 1);
        final fragment =
            job.takeFragments().single as ForumBodyPreparedInlineFragment;
        expect(fragment.view.atomIndices, [i * 2]);
        fragment.close();
        expect(page.cache.activeLeases, 0);
      }
    },
  );

  for (final invalid in [0, 1]) {
    test(
      'page admission rejects zero-height probes and disguised gap columns mode=$invalid',
      () {
        final f = RubySoftSpaceRowFixture(baseGap: true, gapSize: 40);
        addTearDown(f.close);
        final good = _plan(f, 80);
        final dims = good.dimensions.toList();
        final atoms = good.rubyAtoms.toList();
        if (invalid == 0) {
          dims[1] = PlaceholderDimensions(
            size: Size(dims[1].size.width, 0),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 0,
          );
        } else {
          atoms[1] = ForumBodyRubyAtomPlan.column(
            request: ForumBodyRubyColumnRequest(
              base: f.softSpace.nativeRequests[0],
              annotation: f.softSpace.nativeRequests[1],
            ),
          );
        }
        expect(
          () => ForumBodyInlinePageContent.atoms(
            content: good.content,
            dimensions: dims,
            rubyAtoms: atoms,
          ),
          throwsArgumentError,
        );
      },
    );
  }

  test(
    'owner invalidation after visible glyph acquisition releases the entire current page',
    () {
      final f = RubySoftSpaceRowFixture(ranks: 80, gapSize: 1);
      addTearDown(f.close);
      final input = _plan(f, 41, bands: true);
      final page = RubyAtomPageFixture.compose(
        input: input,
        planning: f.cache,
        width: 41,
        height: 500,
        entries: 5,
      );
      addTearDown(page.close);
      var current = true;
      final job = page.open(
        0,
        ensureOwner: () {
          if (!current) throw StateError('retired test owner');
        },
      );
      for (
        var i = 0;
        page.cache.activeLeases < job.expectedNativeLeaseCount && i < 30000;
        i++
      ) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(page.cache.activeLeases, 243);
      expect(job.isReady, isFalse);
      current = false;
      expect(() => job.advance(maxFragments: 1, maxParts: 1), throwsStateError);
      expect(page.cache.activeLeases, 0);
      expect(() => job.takeFragments(), throwsStateError);
    },
  );

  test('actual empty RT fences produce no opposite glyph or selection', () {
    final f = RubySoftSpaceRowFixture(
      baseGap: true,
      annotationGap: false,
      emptyAnnotations: true,
      gapSize: 80,
    );
    addTearDown(f.close);
    final input = _plan(f, 120);
    final page = RubyAtomPageFixture.compose(
      input: input,
      planning: f.cache,
      width: 120,
      height: 500,
      entries: 4,
    );
    addTearDown(page.close);
    final job = page.open(0);
    expect(job.expectedNativeLeaseCount, 4);
    page.finish(job, q: 1);
    final fragment =
        job.takeFragments().single as ForumBodyPreparedInlineFragment;
    expect(fragment.nativeLeases.length, 4);
    for (final context in input.content.contexts) {
      final boxes = fragment.view.selectionBoxes(
        context.startUtf16,
        context.endUtf16,
      );
      expect(
        boxes,
        context.startUtf16 == context.endUtf16 ? isEmpty : isNotEmpty,
      );
    }
    fragment.close();
    expect(page.cache.activeLeases, 0);
  });
}
