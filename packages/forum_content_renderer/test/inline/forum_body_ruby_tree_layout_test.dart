import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_layout.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart';

import 'test_support/unprojected_ruby_fixture.dart';

ForumBodyRubyTreeInput _input(String html) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'visible-nested-tree',
    conversionIdentity: 'none',
  );
  final group = readAuthoredRuby(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final work = ForumBodyRubyTreeInputPreparation(group: group, maxWidth: 500);
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeInput();
  } finally {
    work.close();
  }
}

ForumBodyParagraphCache _cache(int entries) => ForumBodyParagraphCache(
  maxEntries: entries,
  maxEstimatedBytes: 16 * 1024 * 1024,
);

ForumBodyRubyTreeMetrics _measure(
  ForumBodyRubyTreeInput input,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
}) {
  final work = ForumBodyRubyTreeMetricsPreparation(
    input: input,
    cache: cache,
    ensureOwner: () {},
    textScaler: scaler,
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeMetrics();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeLayout _prepare(
  ForumBodyRubyTreeInput input,
  ForumBodyRubyTreeMetrics metrics,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  final work = ForumBodyRubyTreePreparation(
    input: input,
    metrics: metrics,
    cache: cache,
    ensureOwner: () {},
  );
  try {
    var calls = 0;
    while (!work.isReady) {
      final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.formatUnitsPrepared, inInclusiveRange(1, quantum));
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      expect(++calls, lessThan(10000));
    }
    return work.takeLayout();
  } finally {
    work.close();
  }
}

const _html =
    '<ruby style="color:red"><rb><ruby>AB'
    '<rt style="font-size:10px;color:blue">xy</rt></ruby></rb>'
    '<rt style="font-size:8px;color:green">WXYZAB</rt></ruby>';

const _mixedHtml =
    '<ruby><rb>L<ruby>A<rt style="font-size:10px">x</rt></ruby>R</rb>'
    '<rt style="font-size:8px">z</rt></ruby>';

const _outerColumnsHtml =
    '<ruby><rb><ruby>A<rt style="font-size:10px">x</rt></ruby></rb>'
    '<rb>B</rb><rtc style="font-size:8px"><rt>a</rt><rt>b</rt></rtc></ruby>';

Future<List<int>> _pixels(void Function(Canvas) paint, int ratio) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(100 * ratio, 160 * ratio);
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

  test(
    'multi-column tree only rebinds alignment from the same measured graph',
    () {
      final input = _input(_outerColumnsHtml);
      final cache = _cache(16);
      try {
        final metrics = _measure(input, cache);
        final segment = metrics.root.segment!;
        final aligned = segment.alignedTo(segment.level);
        expect(segment.hasSameMeasuredInput(aligned), isTrue);
        final current = metrics.withRootSegment(aligned);
        expect(current.input, same(input));
        expect(current.root.segment, same(aligned));
        final foreign = _measure(
          _input(_outerColumnsHtml),
          cache,
        ).root.segment!;
        expect(segment.hasSameMeasuredInput(foreign), isFalse);
        expect(() => metrics.withRootSegment(foreign), throwsArgumentError);
        final view = _prepare(input, current, cache);
        view.close();
        expect(cache.activeLeases, 0);
      } finally {
        cache.close();
      }
    },
  );

  test('equal foreign group geometry cannot replace a measured tree root', () {
    final input = _input(_html), cache = _cache(16);
    try {
      final metrics = _measure(input, cache),
          foreign = _measure(input, cache).root.group!,
          root = metrics.root.group!;
      expect(foreign.size, root.size);
      expect(foreign.baseline, root.baseline);
      expect(root.hasSameMeasuredInput(foreign), isFalse);
      expect(() => metrics.withRootGroup(foreign), throwsArgumentError);
      final aligned = root.alignedTo(ForumBodyRubyLevelMetrics.single(root));
      expect(root.hasSameMeasuredInput(aligned), isTrue);
      final current = metrics.withRootGroup(aligned);
      expect(current.root.group, same(aligned));
      final view = _prepare(input, current, cache);
      view.close();
      expect(cache.activeLeases, 0);
    } finally {
      cache.close();
    }
  });

  test(
    'multi-column visible cache miss and foreign pins preserve the same transaction',
    () {
      final input = _input(_outerColumnsHtml);
      final sourceCache = _cache(16);
      final metrics = _measure(input, sourceCache);
      sourceCache.close();
      final cache = _cache(5);
      final extra = _input('<ruby>Z<rt>z</rt></ruby>');
      final pinned = cache.acquire(
        content: (extra.nodes.first as ForumBodyRubyTreeText).content,
        width: 500,
      );
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        while (!work.cacheMiss) {
          work.advance(maxParts: 1, cachedOnly: true);
        }
        expect(cache.layoutBuildCount, 1);
        var waiting = false;
        for (var i = 0; !waiting && i < 10000; i++) {
          waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
        }
        expect(waiting, isTrue);
        final held = work.nativeLeases.toList();
        expect(held, hasLength(4));
        final builds = cache.layoutBuildCount;
        expect(work.advance().formatUnitsPrepared, 0);
        expect(work.nativeLeases, orderedEquals(held));
        expect(cache.layoutBuildCount, builds);
        pinned.release();
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        final view = work.takeLayout();
        expect(view.nativeLeases, containsAll(held));
        expect(view.nativeLeases, hasLength(5));
        view.close();
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        pinned.release();
        cache.close();
      }
    },
  );

  test(
    'mixed metrics and visible cold-cache paths resume without native work',
    () {
      final input = _input(_mixedHtml);
      final cache = _cache(16);
      final metricsJob = ForumBodyRubyTreeMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        for (var i = 0; !metricsJob.cacheMiss && i < 10000; i++) {
          metricsJob.advance(maxParts: 1, cachedOnly: true);
        }
        expect(metricsJob.cacheMiss, isTrue);
        expect(cache.layoutBuildCount, 0);
        while (!metricsJob.isReady) {
          final step = metricsJob.advance(maxParts: 1);
          expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        }
        final metrics = metricsJob.takeMetrics();
        expect(metrics.nativeHandleCount, 4);
        expect(metrics.nativeFootprint, hasLength(4));
        expect(cache.activeLeases, 0);
        cache.close();

        final visibleCache = _cache(16);
        final work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: visibleCache,
          ensureOwner: () {},
        );
        try {
          for (var i = 0; !work.cacheMiss && i < 10000; i++) {
            work.advance(maxParts: 1, cachedOnly: true);
          }
          expect(work.cacheMiss, isTrue);
          expect(visibleCache.layoutBuildCount, 0);
          expect(visibleCache.pictureBuildCount, 0);
          while (!work.isReady) {
            work.advance(maxParts: 1);
          }
          work.takeLayout().close();
          final builds = visibleCache.layoutBuildCount;
          final pictures = visibleCache.pictureBuildCount;
          _prepare(input, metrics, visibleCache, cachedOnly: true).close();
          expect(visibleCache.layoutBuildCount, builds);
          expect(visibleCache.pictureBuildCount, pictures);
          expect(visibleCache.activeLeases, 0);
        } finally {
          work.close();
          visibleCache.close();
        }
      } finally {
        metricsJob.close();
        cache.close();
      }
    },
  );

  test('mixed inner parent is charged before shaping with owned prefix', () {
    final input = _input(_mixedHtml);
    final sourceCache = _cache(16);
    final metrics = _measure(input, sourceCache);
    sourceCache.close();
    for (final prefixOwned in [false, true]) {
      // A/x share one glyph-band key; the real child parent and z are distinct.
      final cache = _cache(prefixOwned ? 3 : 2);
      final extra = _input('<ruby>Z<rt>z</rt></ruby>');
      final prefix = prefixOwned
          ? cache.acquire(
              content: (extra.nodes.first as ForumBodyRubyTreeText).content,
              width: 500,
            )
          : null;
      final before = cache.layoutBuildCount;
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () => [?prefix],
      );
      try {
        expect(
          () {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          },
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
        expect(cache.layoutBuildCount, before);
        expect(cache.activeLeases, prefixOwned ? 1 : 0);
      } finally {
        work.close();
        prefix?.release();
        cache.close();
      }
    }
  });

  test(
    'mixed foreign pin waits retain child handles and resume same transaction',
    () {
      final input = _input(_mixedHtml);
      final sourceCache = _cache(16);
      final metrics = _measure(input, sourceCache);
      sourceCache.close();
      final cache = _cache(3);
      final extra = _input('<ruby>Z<rt>z</rt></ruby>');
      final pinned = cache.acquire(
        content: (extra.nodes.first as ForumBodyRubyTreeText).content,
        width: 500,
      );
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        var waiting = false;
        for (var i = 0; !waiting && i < 10000; i++) {
          waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
        }
        expect(waiting, isTrue);
        final held = work.nativeLeases.toList();
        expect(held, isNotEmpty);
        final builds = cache.layoutBuildCount;
        final pictures = cache.pictureBuildCount;
        expect(work.advance().formatUnitsPrepared, 0);
        expect(work.nativeLeases, orderedEquals(held));
        expect(cache.layoutBuildCount, builds);
        expect(cache.pictureBuildCount, pictures);
        pinned.release();
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        final view = work.takeLayout();
        try {
          expect(view.nativeLeases, containsAll(held));
          expect(view.nativeLeases, hasLength(4));
        } finally {
          view.close();
        }
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        pinned.release();
        cache.close();
      }
    },
  );

  test('mixed plans freeze nonlinear samples for ordinary and ruby fonts', () {
    final input = _input(_mixedHtml);
    final cache = _cache(16);
    final raw = _MutableScaler({20: 30, 10: 12, 8: 9});
    try {
      final metrics = _measure(input, cache, scaler: raw);
      expect(metrics.effectiveScales, {20: 30, 10: 12, 8: 9});
      raw.sizes.updateAll((key, value) => value * 2);
      final calls = raw.calls;
      final view = _prepare(input, metrics, cache);
      try {
        expect(view.size.width, 90);
        expect(view.size.height, closeTo(51, 1e-4));
        for (final member in view.members) {
          final box = view
              .selectionBoxes(
                nodeIndex: member.nodeIndex,
                startUtf16: 0,
                endUtf16: member.content.projection.text.length,
              )
              .single;
          final hit = view.sourceAt(
            Offset(box.left + .1, box.toRect().center.dy),
          );
          expect(
            hit.content,
            same(member.content),
            reason:
                '${member.content.projection.text} -> ${hit.content.projection.text}, $box',
          );
          expect(hit.position.isExact, isTrue);
        }
        expect(raw.calls, calls);
      } finally {
        view.close();
      }
    } finally {
      cache.close();
    }
  });

  test(
    'mixed owner retirement across native and source phases releases late handles',
    () {
      final input = _input(_mixedHtml);
      final sourceCache = _cache(16);
      final metrics = _measure(input, sourceCache);
      sourceCache.close();
      final countCache = _cache(16);
      var checks = 0;
      final countWork = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: countCache,
        ensureOwner: () {
          checks++;
        },
      );
      while (!countWork.isReady) {
        countWork.advance(maxParts: 1);
      }
      countWork.close();
      countCache.close();
      // Sample the whole transaction, including native parent adoption and final
      // source/background assembly rather than only the early probe prefix.
      for (final closeAt in {
        1,
        5,
        checks ~/ 3,
        checks ~/ 2,
        checks - 1,
        checks,
      }) {
        final cache = _cache(16);
        var calls = 0;
        late final ForumBodyRubyTreePreparation work;
        work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {
            if (++calls == closeAt) work.close();
          },
        );
        try {
          expect(() {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          }, throwsStateError);
          expect(work.nativeLeases, isEmpty);
          expect(cache.activeLeases, 0);
        } finally {
          work.close();
          cache.close();
        }
      }
    },
  );
  for (final ratio in [1, 3]) {
    for (final nestedRT in [false, true]) {
      for (final outer in ['over', 'under']) {
        for (final inner in ['over', 'under']) {
          test(
            'visible original tree pixels RT=$nestedRT $outer/$inner DPR$ratio',
            () async {
              final html = nestedRT
                  ? '<ruby style="color:red;ruby-position:$outer">AB'
                        '<rt style="font-size:10px;color:blue"><ruby style="ruby-position:$inner">XY'
                        '<rt style="font-size:5px;color:green">xy</rt></ruby></rt></ruby>'
                  : _html
                        .replaceFirst(
                          'color:red',
                          'color:red;ruby-position:$outer',
                        )
                        .replaceFirst(
                          '<rb><ruby>',
                          '<rb><ruby style="ruby-position:$inner">',
                        );
              final input = _input(html);
              final cache = _cache(8);
              final metrics = _measure(input, cache);
              final view = _prepare(input, metrics, cache, quantum: 64);
              final painters = <TextPainter>[];
              try {
                final innerTop = outer == 'over' ? 8.0 : 0.0;
                final expected = nestedRT
                    ? {
                        'AB': Offset(10, outer == 'over' ? 25 : 10),
                        'XY': Offset(
                          20,
                          10 +
                              (outer == 'over' ? 0 : 20) +
                              (inner == 'over' ? 5 : 0),
                        ),
                        'xy': Offset(
                          25,
                          10 +
                              (outer == 'over' ? 0 : 20) +
                              (inner == 'over' ? 0 : 10),
                        ),
                      }
                    : {
                        'AB': Offset(
                          14,
                          10 + innerTop + (inner == 'over' ? 10 : 0),
                        ),
                        'xy': Offset(
                          24,
                          10 + innerTop + (inner == 'over' ? 0 : 20),
                        ),
                        'WXYZAB': Offset(10, 10 + (outer == 'over' ? 0 : 30)),
                      };
                for (final member in view.members) {
                  painters.add(
                    TextPainter(
                      text: TextSpan(
                        text: member.content.projection.text,
                        style: member.content.runs.single.style.textStyle,
                      ),
                      textDirection: TextDirection.ltr,
                    )..layout(),
                  );
                  final at = member.offset + const Offset(10, 10);
                  expect(at, expected[member.content.projection.text]);
                  final boxes = view.selectionBoxes(
                    nodeIndex: member.nodeIndex,
                    startUtf16: 0,
                    endUtf16: member.content.projection.text.length,
                  );
                  expect(boxes, isNotEmpty);
                  final hit = view.sourceAt(boxes.first.toRect().center);
                  expect(hit.nodeIndex, member.nodeIndex);
                  expect(hit.content, same(member.content));
                  expect(hit.position.isExact, isTrue);
                }
                final builds = cache.layoutBuildCount;
                final pictures = cache.pictureBuildCount;
                final actual = await _pixels(
                  (canvas) => view.paint(canvas, const Offset(10, 10)),
                  ratio,
                );
                final reference = await _pixels((canvas) {
                  for (final (index, member) in view.members.indexed) {
                    painters[index].paint(
                      canvas,
                      expected[member.content.projection.text]!,
                    );
                  }
                }, ratio);
                expect(actual, reference);
                expect(cache.layoutBuildCount, builds);
                expect(cache.pictureBuildCount, pictures);
                expect(view.nativeLeases, hasLength(3));
                expect(cache.activeLeases, 3);
                expect(view.isOwnedBy(cache), isTrue);
                final otherOwner = _cache(1);
                expect(view.isOwnedBy(otherOwner), isFalse);
                otherOwner.close();
              } finally {
                view.close();
                for (final painter in painters) {
                  painter.dispose();
                }
                expect(cache.activeLeases, 0);
                cache.close();
                expect(cache.entryCount, 0);
                expect(cache.estimatedRetainedBytes, 0);
              }
            },
          );
        }
      }
    }
  }

  for (final ratio in [1, 3]) {
    test(
      'nested backgrounds precede all glyphs, alpha once, explicit clip DPR$ratio',
      () async {
        final input = _input(
          '<ruby style="color:red;background:rgba(255,0,0,0.5)">'
          '<rb><ruby style="background:rgba(0,0,255,0.5)">A B'
          '<rt style="font-size:10px;color:blue">xy</rt></ruby></rb>'
          '<rt style="font-size:8px;color:green">WXYZABCD</rt></ruby>',
        );
        final cache = _cache(8);
        final view = _prepare(input, _measure(input, cache), cache);
        final painters = <TextPainter>[];
        const clip = Rect.fromLTWH(0, 0, 45, 45);
        try {
          expect(view.backgrounds, hasLength(2));
          expect(view.backgrounds.map((b) => b.font.background.color), [
            const Color(0x80ff0000),
            const Color(0x800000ff),
          ]);
          expect(view.backgrounds.map((b) => b.rect), [
            const Rect.fromLTWH(0, 18, 64, 20),
            const Rect.fromLTWH(2, 18, 60, 20),
          ]);
          final offsets = {
            'A B': const Offset(12, 28),
            'xy': const Offset(32, 18),
            'WXYZABCD': const Offset(10, 10),
          };
          for (final member in view.members) {
            painters.add(
              TextPainter(
                text: TextSpan(
                  text: member.content.projection.text,
                  style: member.content.runs.single.style.textStyle,
                ),
                textDirection: TextDirection.ltr,
              )..layout(),
            );
          }
          final actual = await _pixels((canvas) {
            view.paintBackgrounds(canvas, const Offset(10, 10), clip: clip);
            canvas.save();
            canvas.clipRect(clip);
            view.paint(canvas, const Offset(10, 10));
            canvas.restore();
          }, ratio);
          final expected = await _pixels((canvas) {
            canvas.save();
            canvas.clipRect(clip);
            canvas.drawRect(
              const Rect.fromLTWH(10, 28, 64, 20),
              Paint()..color = const Color(0x80ff0000),
            );
            canvas.drawRect(
              const Rect.fromLTWH(12, 28, 60, 20),
              Paint()..color = const Color(0x800000ff),
            );
            for (final (index, member) in view.members.indexed) {
              painters[index].paint(
                canvas,
                offsets[member.content.projection.text]!,
              );
            }
            canvas.restore();
          }, ratio);
          expect(actual, expected);
          final sample = ((35 * ratio) * (100 * ratio) + 40 * ratio) * 4;
          // rawRgba is premultiplied: half-blue over half-red, alpha 3/4.
          expect(actual.sublist(sample, sample + 4), [64, 0, 128, 192]);
        } finally {
          view.close();
          for (final p in painters) {
            p.dispose();
          }
          cache.close();
        }
      },
    );
  }

  test(
    'container leading never grants an exact hit; glyph selection stays local',
    () {
      final input = _input(
        '<ruby><rb style="font-size:30px;line-height:4">'
        '<ruby style="font-size:20px;line-height:1">A<rt style="font-size:10px">x</rt></ruby>'
        '</rb><rt>y</rt></ruby>',
      );
      final cache = _cache(8);
      final view = _prepare(input, _measure(input, cache), cache);
      try {
        expect(view.size.height, 130);
        expect(view.sourceAt(const Offset(5, 15)).position.isExact, isFalse);
        for (final member in view.members) {
          for (final box in view.selectionBoxes(
            nodeIndex: member.nodeIndex,
            startUtf16: 0,
            endUtf16: member.content.projection.text.length,
          )) {
            expect(
              view.sourceAt(box.toRect().center).content,
              same(member.content),
            );
            expect(view.sourceAt(box.toRect().center).position.isExact, isTrue);
          }
        }
        expect(view.sourceAt(const Offset(5, -1)).position.isExact, isFalse);
      } finally {
        view.close();
        cache.close();
      }
    },
  );

  test('empty and missing annotation identities require no native handles', () {
    final input = _input(
      '<ruby><rb><ruby>A<rt></rt></ruby></rb><rtc></rtc><rtc><rt> </rt></rtc></ruby>',
    );
    final cache = _cache(8);
    final view = _prepare(input, _measure(input, cache), cache);
    try {
      expect(view.members, hasLength(3));
      expect(view.members.where((m) => m.lease == null), hasLength(2));
      expect(view.nativeLeases, hasLength(1));
      for (final member in view.members.where((m) => m.lease == null)) {
        expect(member.content.isSourceFree, isFalse);
        expect(
          view.selectionBoxes(
            nodeIndex: member.nodeIndex,
            startUtf16: 0,
            endUtf16: 0,
          ),
          isEmpty,
        );
      }
      expect(view.sourceAt(const Offset(10, 10)).content.projection.text, 'A');
    } finally {
      view.close();
      cache.close();
    }
  });

  test(
    'complete native footprint rejects before shaping, including owned prefix',
    () {
      final input = _input(_html);
      final measureCache = _cache(8);
      final metrics = _measure(input, measureCache);
      measureCache.close();
      for (final withPrefix in [false, true]) {
        final cache = _cache(withPrefix ? 3 : 2);
        final extra = _input('<ruby>Z<rt>z</rt></ruby>');
        final prefix = withPrefix
            ? cache.acquire(
                content: (extra.nodes.first as ForumBodyRubyTreeText).content,
                width: 500,
              )
            : null;
        final before = cache.layoutBuildCount;
        final work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
          additionalOwnedLeases: () => [?prefix],
        );
        try {
          expect(
            () {
              while (!work.isReady) {
                work.advance(maxParts: 1);
              }
            },
            throwsA(
              isA<ForumBodyParagraphBudgetException>().having(
                (e) => e.failure,
                'failure',
                ForumBodyParagraphBudgetFailure.content,
              ),
            ),
          );
          expect(cache.layoutBuildCount, before);
          expect(cache.activeLeases, withPrefix ? 1 : 0);
          expect(work.nativeLeases, isEmpty);
        } finally {
          work.close();
          prefix?.release();
          cache.close();
        }
      }
    },
  );

  test(
    'external pins wait without restarting adopted leaves or the tree cursor',
    () {
      final input = _input(_html);
      final cache = _cache(3);
      final metrics = _measure(input, cache);
      final extra = _input('<ruby>Z<rt>z</rt></ruby>');
      final pinned = cache.acquire(
        content: (extra.nodes.first as ForumBodyRubyTreeText).content,
        width: 500,
      );
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        var waiting = false;
        while (!waiting) {
          waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
        }
        final held = work.nativeLeases.toList();
        expect(held, hasLength(2));
        final builds = cache.layoutBuildCount;
        expect(work.advance().formatUnitsPrepared, 0);
        expect(work.nativeLeases, orderedEquals(held));
        expect(cache.layoutBuildCount, builds);
        pinned.release();
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        final view = work.takeLayout();
        expect(view.nativeLeases.take(2), orderedEquals(held));
        view.close();
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        pinned.release();
        cache.close();
      }
    },
  );

  test(
    'cached-only cold miss resumes; warm preparation does no native work',
    () {
      final input = _input(_html);
      final sourceCache = _cache(8);
      final metrics = _measure(input, sourceCache);
      sourceCache.close();
      final cache = _cache(8);
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        while (!work.cacheMiss) {
          work.advance(maxParts: 1, cachedOnly: true);
        }
        expect(cache.layoutBuildCount, 0);
        expect(cache.activeLeases, 0);
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        work.takeLayout().close();
        final builds = cache.layoutBuildCount;
        _prepare(input, metrics, cache, cachedOnly: true, quantum: 64).close();
        expect(cache.layoutBuildCount, builds);
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        cache.close();
      }
    },
  );

  test(
    'shared native band keeps exact nonlinear samples and all picture costs',
    () async {
      var input = _input(_html);
      final contents = input.nodes
          .whereType<ForumBodyRubyTreeText>()
          .where((n) => n.needsNative)
          .map((n) => n.content)
          .toList();
      final band = ForumBodyTextBandContent(contexts: contents);
      input = input.mapRequests(
        (old) => ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: contents.indexOf(old.content),
        ),
      );
      final cache = _cache(1);
      final raw = _MutableScaler({20: 30, 10: 12, 8: 9});
      final metrics = _measure(input, cache, scaler: raw);
      raw.sizes.updateAll((key, value) => value * 2);
      final calls = raw.calls;
      final view = _prepare(input, metrics, cache, quantum: 64);
      final painters = <TextPainter>[];
      try {
        expect(view.size.width, closeTo(60, 1e-4));
        expect(view.size.height, closeTo(51, 1e-4));
        expect(metrics.textScaler.scale(20), 30);
        expect(metrics.textScaler.scale(10), 12);
        expect(metrics.textScaler.scale(8), 9);
        expect(calls, 3);
        expect(raw.calls, calls);
        expect(cache.entryCount, 1);
        expect(cache.activeLeases, 3);
        expect(cache.preparedPictureCount, 1);
        expect(
          view.nativeLeases.every((l) => l is ForumBodyTextBandChildLease),
          isTrue,
        );
        for (final member in view.members) {
          painters.add(
            TextPainter(
              text: TextSpan(
                text: member.content.projection.text,
                style: member.content.runs.single.style.textStyle,
              ),
              textDirection: TextDirection.ltr,
              textScaler: metrics.textScaler,
            )..layout(),
          );
          final boxes = view.selectionBoxes(
            nodeIndex: member.nodeIndex,
            startUtf16: 0,
            endUtf16: member.content.projection.text.length,
          );
          expect(
            view.sourceAt(boxes.first.toRect().center).content,
            same(member.content),
          );
        }
        const expectedOffsets = {
          'AB': Offset(10, 31),
          'xy': Offset(28, 19),
          'WXYZAB': Offset(13, 10),
        };
        final before = cache.pictureBuildCount;
        for (final ratio in [1, 3]) {
          final actual = await _pixels(
            (canvas) => view.paint(canvas, const Offset(10, 10)),
            ratio,
          );
          final expected = await _pixels((canvas) {
            for (final (index, member) in view.members.indexed) {
              painters[index].paint(
                canvas,
                expectedOffsets[member.content.projection.text]!,
              );
            }
          }, ratio);
          expect(actual, expected);
        }
        expect(cache.pictureBuildCount, before);
        expect(raw.calls, calls);
      } finally {
        view.close();
        for (final painter in painters) {
          painter.dispose();
        }
        cache.close();
      }
    },
  );

  test(
    'foreign input/request identities and retired current leaves cannot publish',
    () {
      final input = _input(_html);
      final cache = _cache(8);
      final metrics = _measure(input, cache);
      try {
        expect(
          () => ForumBodyRubyTreePreparation(
            input: _input(_html),
            metrics: metrics,
            cache: cache,
            ensureOwner: () {},
          ),
          throwsArgumentError,
        );
        final other = _input('<ruby>Z<rt>z</rt></ruby>');
        expect(
          () => input.mapRequests(
            (old) => ForumBodyTextRequest.paragraph(
              (other.nodes.first as ForumBodyRubyTreeText).content,
            ),
          ),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
        final work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
        );
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        work.nativeLeases.first.release();
        expect(() => work.takeLayout(), throwsStateError);
        expect(cache.activeLeases, 0);
        work.close();
      } finally {
        cache.close();
      }
    },
  );

  test(
    'deep shared-band leaves with identical text keep distinct DOM sources',
    () {
      var html = 'A';
      for (var depth = 0; depth < 30; depth++) {
        html =
            '<ruby style="font-size:20px"><rb>$html</rb>'
            '<rt style="font-size:1px">x</rt></ruby>';
      }
      var input = _input(html);
      final contents = input.nodes
          .whereType<ForumBodyRubyTreeText>()
          .where((n) => n.needsNative)
          .map((n) => n.content)
          .toList();
      final band = ForumBodyTextBandContent(contexts: contents);
      input = input.mapRequests(
        (old) => ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: contents.indexOf(old.content),
        ),
      );
      final cache = _cache(1);
      final view = _prepare(input, _measure(input, cache), cache);
      try {
        expect(view.members, hasLength(31));
        expect(view.nativeLeases, hasLength(31));
        expect(cache.entryCount, 1);
        expect(cache.preparedPictureCount, 1);
        expect(view.members.map((m) => m.content.path).toSet(), hasLength(31));
        for (final member in view.members) {
          final boxes = view.selectionBoxes(
            nodeIndex: member.nodeIndex,
            startUtf16: 0,
            endUtf16: 1,
          );
          final hit = view.sourceAt(boxes.single.toRect().center);
          expect(hit.content, same(member.content));
          expect(hit.position.isExact, isTrue);
        }
      } finally {
        view.close();
        expect(cache.activeLeases, 0);
        cache.close();
      }
    },
  );

  test(
    'cancellation at probe/native/position phases releases every adopted leaf',
    () {
      final input = _input(_html);
      final measureCache = _cache(8);
      final metrics = _measure(input, measureCache);
      measureCache.close();
      for (final cancelAfter in [0, 1, 5, 10, 15, 20, 30, 45]) {
        final cache = _cache(8);
        final work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
        );
        for (var step = 0; step < cancelAfter && !work.isReady; step++) {
          work.advance(maxParts: 1);
        }
        work.close();
        work.close();
        expect(cache.activeLeases, 0);
        expect(work.nativeLeases, isEmpty);
        expect(() => work.advance(), throwsStateError);
        cache.close();
      }
    },
  );

  test(
    'reentrant owner retirement rolls back late leases and prepared snapshots',
    () {
      final input = _input(_html);
      final sourceCache = _cache(8);
      final metrics = _measure(input, sourceCache);
      sourceCache.close();
      final countCache = _cache(8);
      var totalChecks = 0;
      final countWork = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: countCache,
        ensureOwner: () {
          totalChecks++;
        },
      );
      while (!countWork.isReady) {
        countWork.advance(maxParts: 1);
      }
      countWork.close();
      countCache.close();
      for (final closeAt in [1, 5, 15, 25, totalChecks]) {
        final cache = _cache(8);
        var calls = 0;
        late final ForumBodyRubyTreePreparation work;
        work = ForumBodyRubyTreePreparation(
          input: input,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {
            if (++calls == closeAt) work.close();
          },
        );
        try {
          expect(() {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          }, throwsStateError);
          expect(cache.activeLeases, 0);
          expect(work.nativeLeases, isEmpty);
        } finally {
          work.close();
          cache.close();
        }
      }
    },
  );
}

final class _MutableScaler extends TextScaler {
  _MutableScaler(this.sizes);
  // Deliberately change the backing values AFTER capture to prove that native
  // resources retain the captured inputs, rather than this test caller.
  final Map<double, double> sizes;
  final _calls = <double>[];
  int get calls => _calls.length;
  @override
  double scale(double fontSize) {
    _calls.add(fontSize);
    return sizes[fontSize]!;
  }

  @override
  double get textScaleFactor => scale(20) / 20;
}
