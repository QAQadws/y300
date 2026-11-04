import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_inline_page_preparation.dart'
    show ForumBodyInlinePagePreparation;

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache({int entries = 512}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(c.close);
  return c;
}

MixedEmphasisAllocatedSource _source(
  ForumBodyParagraphCache cache,
  String child, {
  double width = 300,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  String prefix = '',
  String suffix = '',
  String style = 'text-emphasis:circle;line-height:.4',
}) => measureMixedEmphasisAllocatedSource(
  MixedEmphasisParentFixture(
    child,
    width: width,
    direction: direction,
    prefix: prefix,
    suffix: suffix,
    parentStyle: style,
  ),
  cache,
  scaler: scaler,
);

ForumBodyInlineEmphasisChildPreparation _work(
  MixedEmphasisAllocatedSource s,
  ForumBodyParagraphCache c, {
  TextScaler scaler = TextScaler.noScaling,
  int start = 0,
  int? end,
  void Function()? guard,
  void Function()? visible,
  int backgrounds = 32768,
  int atoms = 512,
  int ownedLimit = 32768,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
}) => ForumBodyInlineEmphasisChildPreparation(
  allocation: s.allocation,
  natural: s.natural,
  cache: c,
  expectedTextScaler: scaler,
  ensureOwner: guard ?? () {},
  ensureVisibleOwner: visible,
  startLine: start,
  endLine: end,
  maxBackgrounds: backgrounds,
  maxAtoms: atoms,
  maxPrefixLeases: ownedLimit,
  additionalOwnedLeases: owned ?? () => [s.source],
);

({ForumBodyInlineEmphasisChildView view, int parts}) _finish(
  ForumBodyInlineEmphasisChildPreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(100000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount),
          step = work.advance(maxParts: quantum);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
      expect(step.picturesRecorded, cache.pictureBuildCount - before.$2);
      expect(
        step.nativeLayoutsBuilt + step.picturesRecorded,
        inInclusiveRange(0, 1),
      );
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      parts += step.partsPrepared;
    }
    final view = work.takeView();
    expect(work.nativeLeases, isEmpty);
    return (view: view, parts: parts);
  } finally {
    work.close();
  }
}

ForumBodyInlineParagraphView _naturalView(
  MixedEmphasisAllocatedSource s,
  ForumBodyParagraphCache cache,
) {
  final m = s.allocation.input.natural,
      p = m.page,
      input = ForumBodyInlinePageContent.atoms(
        content: s.natural.content,
        dimensions: p.dimensions,
        rubyAtoms: p.rubyAtoms,
        trimmedAtomIndices: p.trimmedAtomIndices,
        containerBackgrounds: p.containerBackgrounds,
        rootFonts: p.rootFonts,
        layoutMode: p.layoutMode,
      );
  final composer = ForumBodyTextPageComposer(
    identity: input.identity,
    layoutId: 'actual-child-control',
    width: s.natural.layout.width,
    height: 100000,
    maxPages: 8,
    maxFragments: 8,
  );
  try {
    composer.appendInline(
      lease: m.parentRequest.acquire(
        cache,
        width: m.requestWidth,
        textScaler: m.textScaler,
        cachedOnly: false,
      )!,
      paragraphIndex: 0,
      left: 0,
      spaceBefore: 0,
      spaceAtPageStart: 0,
    );
    while (!composer.needsInput) {
      composer.advance(maxLines: 1);
    }
    composer.finish();
    final fragment = composer.snapshot.single.fragments.single;
    ForumBodyInlinePagePreparation? job;
    job = ForumBodyInlinePagePreparation(
      input: input,
      fragment: fragment,
      identity: input.identity,
      cache: cache,
      textScaler: m.textScaler,
      ensureOwner: () {},
      ownedPageLeases: () => [s.natural, s.source, ...?job?.nativeLeases],
    );
    try {
      for (var n = 0; n < 100000; n++) {
        final result = job.advance(cachedOnly: false, maxParts: 1);
        if (result.view case final view?) {
          addTearDown(view.close);
          return view;
        }
      }
      throw StateError('Natural control stalled');
    } finally {
      job.close();
    }
  } finally {
    composer.close();
  }
}

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  Size size,
  double dpr,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr));
  final pic = rec.endRecording();
  try {
    final image = await pic.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    pic.dispose();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache cache, int index) {
  final document = const ForumBodyParser().parse(
        html: '<p>child-pin-$index</p>',
        sourceId: 'child-pin-$index',
        conversionIdentity: 'none',
      ),
      styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: 'child-pin',
          linkColor: const Color(0xff0000ff),
        ),
      );
  final lease = cache.acquire(
    content: const ForumBodyParagraphContentBuilder().build(
      document: document,
      path: '0',
      styles: styles,
    ),
    width: 300,
  );
  addTearDown(lease.release);
  return lease;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    test('actual final child source and ownership $i', () {
      final cache = _cache(),
          s = _source(cache, child),
          before = cache.activeLeases,
          result = _finish(_work(s, cache), cache).view;
      expect(
        result.atomIndices.toList(),
        s.natural.layout
            .fragment(0, s.natural.layout.lineCount)
            .atomIndices
            .toList(),
      );
      for (final atom in result.atomIndices) {
        expect(
          result.originForAtom(atom),
          s.allocation.children[atom]!.offset - Offset(0, result.top),
        );
      }
      expect(result.isActive, isTrue);
      expect(cache.activeLeases, greaterThan(before));
      result.close();
      result.close();
      expect(cache.activeLeases, before);
      expect(s.natural.isActive, isTrue);
      expect(s.source.isActive, isTrue);
    });
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        test('actual complete child pixels $i/$direction/$scaler', () async {
          final cache = _cache(),
              s = _source(
                cache,
                child,
                direction: direction,
                scaler: scaler,
                prefix: 'P',
                suffix: 'Q',
              ),
              control = _naturalView(s, cache),
              result = _finish(
                _work(s, cache, scaler: scaler),
                cache,
                quantum: 512,
              ).view;
          addTearDown(result.close);
          expect(s.allocation.rows, hasLength(1));
          const margin = Offset(30, 30);
          final size = Size(400, result.height + 80),
              expected = await _pixels(
                (c) {
                  // Compare children without the standard view's hard viewport
                  // clip, which changes fractional boundary alpha. The slot
                  // origin comes from the independent actual natural layout.
                  for (final atom in control.atomIndices) {
                    control.paintBoundAtomAt(
                      c,
                      margin +
                          s.natural.layout.atomBoxes[atom].toRect().topLeft +
                          s.allocation.rows.single.naturalOffset,
                      atom,
                    );
                  }
                },
                size,
                1.25,
              ),
              actual = await _pixels(
                (c) {
                  result.paintContainerBackgrounds(c, margin);
                  for (final atom in result.atomIndices) {
                    result.paintAtom(c, margin, atom);
                  }
                },
                size,
                1.25,
              );
          expect(expected.where((v) => v != 0), isNotEmpty);
          expect(actual, orderedEquals(expected));
          result.close();
          final before = (cache.layoutBuildCount, cache.pictureBuildCount),
              warm = _finish(
                _work(s, cache, scaler: scaler),
                cache,
                quantum: 512,
              ).view;
          warm.close();
          expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
        });
      }
    }
  }

  test(
    'actual global background rows map to allocated fragment coordinates',
    () async {
      final cache = _cache(),
          child =
              '<ruby style="text-emphasis:none;background-color:rgba(255,0,0,.4)">A<rt>x</rt></ruby>',
          s = _source(
            cache,
            '$child\n$child\n$child',
            style: 'text-emphasis:circle;line-height:.4;white-space:pre-wrap',
          ),
          control = _naturalView(s, cache),
          before = cache.activeLeases;
      expect(s.allocation.rows, hasLength(3));
      expect(control.backgroundRows, hasLength(3));
      expect(() => control.backgroundRows.clear(), throwsUnsupportedError);
      for (var row = 0; row < 3; row++) {
        final result = _finish(
              _work(s, cache, start: row, end: row + 1),
              cache,
            ).view,
            natural = s.natural.layout.fragment(row, row + 1),
            atom = natural.atomIndices.single,
            region = control.backgroundRows.singleWhere(
              (r) => r.lineIndex == row,
            ),
            offset =
                s.allocation.rows[row].naturalOffset - Offset(0, result.top);
        try {
          expect(result.atomIndices.toList(), [atom]);
          expect(result.backgroundSurfaces, hasLength(1));
          expect(
            result.backgroundSurfaces.single.rect,
            region.rect.shift(offset),
          );
          const margin = Offset(30, 30);
          final size = Size(400, result.height + 80),
              expected = await _pixels(
                (c) {
                  c.drawRect(
                    region.rect.shift(margin + offset),
                    Paint()..color = region.font.background.color,
                  );
                  control.paintBoundAtomAt(
                    c,
                    margin +
                        s.allocation.children[atom]!.offset -
                        Offset(0, result.top),
                    atom,
                  );
                },
                size,
                1.5,
              ),
              actual = await _pixels(
                (c) {
                  result.paintContainerBackgrounds(c, margin);
                  result.paintAtom(c, margin, atom);
                },
                size,
                1.5,
              );
          expect(actual, orderedEquals(expected));
          final recorder = ui.PictureRecorder();
          try {
            expect(
              () => result.paintAtom(
                Canvas(recorder),
                Offset.zero,
                (atom + 1) % 3,
              ),
              throwsA(isA<ForumBodyInlineViewException>()),
            );
          } finally {
            recorder.endRecording().dispose();
          }
        } finally {
          result.close();
        }
        expect(cache.activeLeases, before);
      }
    },
  );

  test(
    'cached miss retains actual children then resumes in the same transaction',
    () {
      final cache = _cache(), s = _source(cache, mixedEmphasisChildren[1]);
      cache.clearUnpinned();
      final before = cache.activeLeases, work = _work(s, cache);
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(100000));
        final counts = (cache.layoutBuildCount, cache.pictureBuildCount),
            step = work.advance(maxParts: 32, cachedOnly: true);
        expect(step.waitingForLayoutBudget, isFalse);
        expect((cache.layoutBuildCount, cache.pictureBuildCount), counts);
      }
      expect(work.isReady, isFalse);
      expect(work.nativeLeases, isNotEmpty);
      final result = _finish(work, cache, quantum: 512).view;
      result.close();
      expect(cache.activeLeases, before);
    },
  );

  test(
    'external pins wait at a stable revision then resume existing children',
    () {
      final cache = _cache(entries: 16),
          s = _source(cache, mixedEmphasisChildren[1]);
      cache.clearUnpinned();
      final pins = [for (var i = 0; i < 13; i++) _pin(cache, i)],
          before = cache.activeLeases,
          work = _work(s, cache);
      for (var n = 0; ; n++) {
        expect(n, lessThan(100000));
        if (work.advance(maxParts: 32).waitingForLayoutBudget) break;
      }
      final counts = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      );
      for (var i = 0; i < 4; i++) {
        final step = work.advance(maxParts: 32);
        expect(step.waitingForLayoutBudget, isTrue);
        expect(step.partsPrepared, 0);
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), counts);
      for (final pin in pins) {
        pin.release();
      }
      _finish(work, cache, quantum: 512).view.close();
      expect(cache.activeLeases, before - pins.length);
    },
  );

  test('caller-owned prefix is included in complete child preflight', () {
    final cache = _cache(entries: 16),
        s = _source(cache, mixedEmphasisChildren[1]);
    cache.clearUnpinned();
    final pins = [for (var i = 0; i < 13; i++) _pin(cache, i)],
        before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        ),
        work = _work(s, cache, owned: () => [s.source, ...pins]);
    expect(
      () => _finish(work, cache),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
  });

  test(
    'retirement in the child-view adoption gap releases unassigned handles',
    () {
      final cache = _cache(),
          s = _source(cache, mixedEmphasisChildren[1]),
          before = cache.activeLeases;
      ForumBodyInlineEmphasisChildPreparation? work;
      var retired = false;
      work = _work(
        s,
        cache,
        guard: () {
          if (work != null &&
              cache.activeLeases > before + work.nativeLeases.length) {
            retired = true;
            work.close();
          }
        },
      );
      expect(() => _finish(work!, cache), throwsStateError);
      expect(retired, isTrue);
      expect(cache.activeLeases, before);
    },
  );

  test(
    'isolated parent cannot substitute for qualified natural source rows',
    () {
      final cache = _cache(),
          s = _source(cache, mixedEmphasisChildren[0]),
          before = cache.activeLeases;
      expect(
        () => ForumBodyInlineEmphasisChildPreparation(
          allocation: s.allocation,
          natural: s.source,
          cache: cache,
          expectedTextScaler: TextScaler.noScaling,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect(cache.activeLeases, before);
      expect(() => _work(s, cache, start: 1, end: 1), throwsRangeError);
      expect(cache.activeLeases, before);
    },
  );

  test(
    'transferred view retains its own parent alias after measurement release',
    () {
      final cache = _cache(),
          s = _source(cache, mixedEmphasisChildren[1]),
          result = _finish(_work(s, cache), cache).view;
      s.natural.release();
      s.source.release();
      expect(result.isActive, isTrue);
      final recorder = ui.PictureRecorder();
      try {
        result.paintAtom(
          Canvas(recorder),
          Offset.zero,
          result.atomIndices.single,
        );
      } finally {
        recorder.endRecording().dispose();
        result.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test('trimmed soft slots reserve no visible child or background', () {
    final cache = _cache(),
        s = _source(cache, mixedEmphasisChildren[5], width: 20),
        before = cache.activeLeases;
    expect(s.allocation.input.natural.page.trimmedAtomIndices, isNotEmpty);
    final result = _finish(_work(s, cache), cache).view;
    for (final i in s.allocation.input.natural.page.trimmedAtomIndices) {
      expect(result.atomIndices, isNot(contains(i)));
      expect(
        () => result.originForAtom(i),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
    }
    result.close();
    expect(cache.activeLeases, before);
  });

  test('cancellation at each resource boundary returns only owned handles', () {
    final cache = _cache(),
        s = _source(cache, mixedEmphasisChildren[1]),
        baseline = cache.activeLeases,
        full = _finish(_work(s, cache), cache);
    full.view.close();
    for (var stop = 0; stop <= full.parts; stop++) {
      final work = _work(s, cache);
      for (var n = 0; n < stop && !work.isReady; n++) {
        work.advance(maxParts: 1);
      }
      work.close();
      work.close();
      expect(work.nativeLeases, isEmpty);
      expect(work.takeView, throwsStateError);
      expect(() => work.advance(), throwsStateError);
      expect(cache.activeLeases, baseline, reason: 'stop $stop');
    }
  });

  test(
    'visible lifetime survives preparation and rejects retired painting',
    () {
      final cache = _cache(),
          s = _source(cache, mixedEmphasisChildren[1]),
          before = cache.activeLeases;
      var preparing = true, visible = true;
      final work = _work(
            s,
            cache,
            guard: () {
              if (!preparing) throw StateError('preparing');
            },
            visible: () {
              if (!visible) throw StateError('visible');
            },
          ),
          result = _finish(work, cache).view;
      preparing = false;
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      try {
        result.paintAtom(canvas, Offset.zero, result.atomIndices.single);
        visible = false;
        expect(
          () => result.paintAtom(canvas, Offset.zero, 0),
          throwsStateError,
        );
        expect(
          () => result.paintContainerBackgrounds(canvas, Offset.zero),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
        result.close();
      }
      expect(cache.activeLeases, before);
    },
  );

  test(
    'bounded metadata and complete expected scaler reject before new native work',
    () {
      final cache = _cache(),
          s = _source(cache, '<ruby style="background:red">A<rt>x</rt></ruby>'),
          before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          );
      expect(
        () => _work(s, cache, atoms: 0),
        throwsA(isA<ForumBodyEmphasisAllocationException>()),
      );
      expect(
        () => _finish(_work(s, cache, scaler: TextScaler.linear(2)), cache),
        throwsA(isA<ForumBodyInlineViewException>()),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      expect(
        () => _finish(_work(s, cache, ownedLimit: 1), cache),
        throwsA(isA<ForumBodyEmphasisAllocationException>()),
      );
      expect(cache.activeLeases, before.$3);
      expect(
        () => _finish(_work(s, cache, backgrounds: 0), cache),
        throwsA(isA<ForumBodyEmphasisAllocationException>()),
      );
      expect(cache.activeLeases, before.$3);
      expect(s.natural.isActive && s.source.isActive, isTrue);
    },
  );

  test(
    'retirement at final handoff releases children and preserves borrowed parents',
    () {
      final cache = _cache(),
          s = _source(cache, mixedEmphasisChildren[1]),
          before = cache.activeLeases;
      var retire = false;
      ForumBodyInlineEmphasisChildPreparation? work;
      work = _work(
        s,
        cache,
        visible: () {
          if (retire) work!.close();
        },
      );
      while (!work.isReady) {
        work.advance(maxParts: 32);
      }
      retire = true;
      expect(work.takeView, throwsStateError);
      expect(cache.activeLeases, before);
    },
  );
}
