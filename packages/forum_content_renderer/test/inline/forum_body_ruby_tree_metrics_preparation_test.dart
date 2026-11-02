import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart';

final class _Parsed {
  _Parsed(String html) {
    final document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'nested-native-tree',
      conversionIdentity: 'none',
    );
    final flow = ForumBodyTextFlowCursor(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        if (flow.current case ForumBodyTextFlowInline(:final content)) {
          input = content;
          group = content.parts
              .whereType<ForumBodyInlineFlowRuby>()
              .first
              .group;
          break;
        }
      }
    } finally {
      flow.close();
    }
  }
  late final ForumBodyInlineFlowContent input;
  late final ForumBodyRubyGroupContent group;
}

ForumBodyRubyTreeInput _tree(
  ForumBodyRubyGroupContent group, {
  int quantum = 1,
}) {
  final work = ForumBodyRubyTreeInputPreparation(group: group, maxWidth: 500);
  try {
    var calls = 0;
    while (!work.isReady) {
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      expect(++calls, lessThan(10000));
    }
    return work.takeInput();
  } finally {
    work.close();
  }
}

ForumBodyParagraphCache _cache({int entries = 64}) => ForumBodyParagraphCache(
  maxEntries: entries,
  maxEstimatedBytes: 16 * 1024 * 1024,
);

ForumBodyRubyTreeMetrics _measure(
  ForumBodyRubyTreeInput tree,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final work = ForumBodyRubyTreeMetricsPreparation(
    input: tree,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    var calls = 0;
    while (!work.isReady) {
      final step = work.advance(maxParts: quantum);
      expect(step.formatUnitsPrepared, inInclusiveRange(1, quantum));
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.nativeLeases, isEmpty);
      expect(cache.activeLeases, 0);
      expect(++calls, lessThan(10000));
    }
    return work.takeMetrics();
  } finally {
    work.close();
  }
}

const _nested =
    '<ruby style="color:red"><rb><ruby>AB'
    '<rt style="font-size:10px;color:blue">xy</rt></ruby></rb>'
    '<rt style="font-size:8px;color:green">WXYZAB</rt></ruby>';

Future<List<int>> _pixels(void Function(Canvas) paint, int ratio) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(80 * ratio, 160 * ratio);
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

  test(
    'original nested RB and RT keep postorder topology and source leaf order',
    () {
      final parsed = _Parsed(
        '<ruby><rb><ruby>A<rt>a</rt></ruby></rb>'
        '<rtc><rt><ruby>B<rt>b</rt></ruby></rt></rtc>'
        '<rtc style="ruby-position:under"><rt>c</rt></rtc></ruby>',
      );
      final tree = _tree(parsed.group);
      final leaves = tree.nodes.whereType<ForumBodyRubyTreeText>().toList();
      expect(leaves.map((l) => l.original.projection.text), [
        'A',
        'a',
        'B',
        'b',
        'c',
      ]);
      final base = parsed.group.base.single as ForumBodyRubyBaseContent;
      final nested = base.parts.single as ForumBodyRubyNestedContent;
      final original =
          nested.groups.single.base.single as ForumBodyRubyTextContent;
      expect(leaves.first.original, same(original.content));
      expect(leaves.first.content, same(original.content));
      for (final (id, node) in tree.nodes.indexed) {
        switch (node) {
          case ForumBodyRubyTreeText():
            expect(node.content.identity, parsed.group.identity);
            expect(node.content.styleRevision, parsed.group.styleRevision);
          case ForumBodyRubyTreeFrame():
            expect(node.child, lessThan(id));
          case ForumBodyRubyTreeGroup():
            expect(node.base, lessThan(id));
            for (final a in node.annotations) {
              if (a.child != null) expect(a.child, lessThan(id));
            }
        }
      }
      final root = tree.nodes.last as ForumBodyRubyTreeGroup;
      expect(root.group, same(parsed.group));
      expect(root.annotations.map((a) => a.side), [
        ForumBodyRubySide.over,
        ForumBodyRubySide.under,
      ]);
      expect(tree.nativeRequests, hasLength(5));
      expect(() => tree.nodes.clear(), throwsUnsupportedError);
      expect(() => tree.nativeRequests.clear(), throwsUnsupportedError);
      // Numeric preparation is not permission to publish a page without binding.
      expect(
        () => ForumBodyInlinePlanInput(parsed.input, 500),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'mixed inline contexts, multiple columns and implicit edge spaces are refused',
    () {
      for (final html in [
        '<ruby>before<ruby>A<rt>a</rt></ruby>after<rt>b</rt></ruby>',
        '<ruby><rb><ruby><rb>A</rb><rb>B</rb><rt>a</rt><rt>b</rt></ruby></rb><rt>x</rt></ruby>',
        '<ruby>A<rt>a</rt><rt>b</rt></ruby>',
        '<ruby> A <rt>a</rt></ruby>',
        '<ruby><rb><ruby></ruby></rb><rt>a</rt></ruby>',
      ]) {
        expect(
          () => _tree(_Parsed(html).group),
          throwsA(isA<ForumBodyParagraphInputException>()),
          reason: html,
        );
      }
    },
  );

  test(
    'compiler and numeric work yield through a deep actual parsed chain',
    () {
      var html = 'A';
      for (var depth = 0; depth < 30; depth++) {
        html =
            '<ruby style="font-size:20px"><rb>$html</rb>'
            '<rt style="font-size:1px">x</rt></ruby>';
      }
      final group = _Parsed(html).group;
      final a = _tree(group);
      final b = _tree(group, quantum: 3);
      expect(a.nodes.length, b.nodes.length);
      final cache = _cache(entries: 1);
      try {
        final first = _measure(a, cache);
        final second = _measure(b, cache, quantum: 64);
        expect(first.box.bounds, second.box.bounds);
        expect(first.box.alphabeticBaseline, second.box.alphabeticBaseline);
        expect(first.nodes, hasLength(a.nodes.length));
        expect(cache.entryCount, 1);
        expect(cache.activeLeases, 0);
      } finally {
        cache.close();
      }
    },
  );

  for (final nestedAnnotation in [false, true]) {
    for (final ratio in [1, 3]) {
      for (final outerSide in ['over', 'under']) {
        for (final childSide in ['over', 'under']) {
          test(
            'actual nested native geometry pixels RT=$nestedAnnotation $outerSide/$childSide DPR$ratio',
            () async {
              final html = nestedAnnotation
                  ? '<ruby style="color:red;ruby-position:$outerSide">AB'
                        '<rt style="font-size:10px;color:blue"><ruby style="ruby-position:$childSide">XY'
                        '<rt style="font-size:5px;color:green">xy</rt></ruby></rt></ruby>'
                  : _nested
                        .replaceFirst(
                          '<ruby style="color:red">',
                          '<ruby style="color:red;ruby-position:$outerSide">',
                        )
                        .replaceFirst(
                          '<rb><ruby>',
                          '<rb><ruby style="ruby-position:$childSide">',
                        );
              final tree = _tree(_Parsed(html).group);
              final cache = _cache();
              final painters = <TextPainter>[];
              final leases = <ForumBodyTextLease>[];
              try {
                final metrics = _measure(tree, cache, quantum: 64);
                final offsets = <int, Offset>{tree.root: const Offset(10, 10)};
                for (var id = tree.root; id >= 0; id--) {
                  final node = tree.nodes[id];
                  final at = offsets[id]!;
                  final numeric = metrics.nodes[id];
                  switch (node) {
                    case ForumBodyRubyTreeText():
                      leases.add(
                        cache.acquire(content: node.content, width: 500),
                      );
                      painters.add(
                        TextPainter(
                          text: TextSpan(
                            text: node.content.projection.text,
                            style: node.content.runs.single.style.textStyle,
                          ),
                          textDirection: TextDirection.ltr,
                        )..layout(),
                      );
                    case ForumBodyRubyTreeFrame():
                      final frame =
                          (numeric as ForumBodyRubyTreeContainerMetrics).frame;
                      offsets[node.child] = at + Offset(0, frame.childTop);
                    case ForumBodyRubyTreeGroup():
                      final box = numeric as ForumBodyRubyTreeContainerMetrics;
                      final origin = at + Offset(0, box.frame.childTop);
                      offsets[node.base] = origin + box.group!.baseOffset;
                      for (final (rank, annotation)
                          in node.annotations.indexed) {
                        if (annotation.child != null) {
                          offsets[annotation.child!] =
                              origin + box.group!.annotations[rank].offset;
                        }
                      }
                  }
                }
                expect(metrics.box.bounds.width, nestedAnnotation ? 40 : 48);
                expect(metrics.box.bounds.height, nestedAnnotation ? 35 : 38);
                final innerTop = outerSide == 'over' ? 8.0 : 0.0;
                final baseY = innerTop + (childSide == 'over' ? 10 : 0);
                final childY = innerTop + (childSide == 'over' ? 0 : 20);
                final outerY = outerSide == 'over' ? 0.0 : 30.0;
                final expectedByText = nestedAnnotation
                    ? {
                        'AB': Offset(10, outerSide == 'over' ? 25 : 10),
                        'XY': Offset(
                          20,
                          10 +
                              (outerSide == 'over' ? 0 : 20) +
                              (childSide == 'over' ? 5 : 0),
                        ),
                        'xy': Offset(
                          25,
                          10 +
                              (outerSide == 'over' ? 0 : 20) +
                              (childSide == 'over' ? 0 : 10),
                        ),
                      }
                    : {
                        'AB': Offset(14, 10 + baseY),
                        'xy': Offset(24, 10 + childY),
                        'WXYZAB': Offset(10, 10 + outerY),
                      };
                final textIds = tree.nodes.indexed
                    .where((e) => e.$2 is ForumBodyRubyTreeText)
                    .map((e) => e.$1)
                    .toList()
                    .reversed
                    .toList();
                final actual = await _pixels((canvas) {
                  for (final (index, id) in textIds.indexed) {
                    leases[index].layout.paint(canvas, offsets[id]!);
                  }
                }, ratio);
                final expected = await _pixels((canvas) {
                  for (final (index, id) in textIds.indexed) {
                    final node = tree.nodes[id] as ForumBodyRubyTreeText;
                    painters[index].paint(
                      canvas,
                      expectedByText[node.content.projection.text]!,
                    );
                  }
                }, ratio);
                expect(actual, expected);
              } finally {
                for (final lease in leases) {
                  lease.release();
                }
                for (final painter in painters) {
                  painter.dispose();
                }
                cache.close();
                expect(cache.activeLeases, 0);
                expect(cache.entryCount, 0);
                expect(cache.estimatedRetainedBytes, 0);
              }
            },
          );
        }
      }
    }
  }

  test(
    'annotation trim windows keep original leaf and omitted source affinity',
    () {
      final tree = _tree(
        _Parsed(
          '<ruby><rb><ruby>A<rt> x </rt></ruby></rb>'
          '<rt> </rt></ruby>',
        ).group,
      );
      final leaves = tree.nodes.whereType<ForumBodyRubyTreeText>().toList();
      expect(leaves.map((n) => n.original.projection.text), ['A', ' x ', ' ']);
      expect(leaves.map((n) => n.content.projection.text), ['A', 'x', '']);
      expect(leaves[1].content, isNot(same(leaves[1].original)));
      expect(leaves[1].content.path, leaves[1].original.path);
      expect(
        leaves[1].content.projection.sourceAtUtf16(0).sourceRune,
        leaves[1].original.projection.sourceAtUtf16(1).sourceRune,
      );
      expect(leaves.last.needsNative, isFalse);
      expect(leaves.last.content.isSourceFree, isFalse);
      expect(tree.nativeRequests, hasLength(2));
      expect(
        () => _tree(_Parsed('<ruby>A<rt> \u0301x</rt></ruby>').group),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'nested root background uses its own natural font with the effective linebox',
    () {
      final tree = _tree(
        _Parsed(
          '<ruby><rb><ruby style="font-size:30px;line-height:4;'
          'background:rgba(255,0,0,0.5)"><rb style="font-size:20px;line-height:1">A</rb>'
          '<rt style="font-size:10px">x</rt></ruby></rb><rt>y</rt></ruby>',
        ).group,
      );
      final cache = _cache(entries: 1);
      try {
        final metrics = _measure(tree, cache, quantum: 64);
        final id = tree.nodes.indexWhere(
          (n) => n is ForumBodyRubyTreeGroup && n.background != null,
        );
        final root = metrics.nodes[id] as ForumBodyRubyTreeContainerMetrics;
        expect(root.font.height, 120);
        expect(root.backgroundFont!.height, 30);
        expect(root.frame.size.height, 120);
        expect(root.group!.size.height, 30);
        expect(
          root.backgroundFont!.background,
          same((tree.nodes[id] as ForumBodyRubyTreeGroup).background),
        );
        expect(cache.activeLeases, 0);
      } finally {
        cache.close();
      }
    },
  );

  test(
    'empty RT and missing RTC ranks retain identity without glyph handles',
    () {
      final parsed = _Parsed(
        '<ruby><rb><ruby>A<rt></rt></ruby></rb>'
        '<rtc></rtc><rtc><rt></rt></rtc></ruby>',
      );
      final tree = _tree(parsed.group);
      final empty = tree.nodes
          .whereType<ForumBodyRubyTreeText>()
          .where((n) => n.content.projection.text.isEmpty)
          .toList();
      expect(empty, hasLength(2));
      expect(
        empty.every((n) => !n.needsNative && !n.original.isSourceFree),
        isTrue,
      );
      expect(tree.nativeRequests, hasLength(1));
      final cache = _cache();
      try {
        final metrics = _measure(tree, cache);
        for (final (id, node) in tree.nodes.indexed) {
          if (node is ForumBodyRubyTreeText && !node.needsNative) {
            expect(metrics.nodes[id].box, isNull);
          }
        }
        final root = metrics.nodes.last as ForumBodyRubyTreeContainerMetrics;
        expect(root.group!.annotations.every((a) => !a.hasAnnotation), isTrue);
      } finally {
        cache.close();
      }
    },
  );

  test(
    'structured RB keeps its own linebox and existing native highlight policy',
    () {
      final parsed = _Parsed(
        '<ruby><rb style="font-size:30px;line-height:4;'
        'background:rgba(255,0,0,0.5)"><ruby style="font-size:20px;line-height:1">'
        'A<rt style="font-size:10px">x</rt></ruby></rb><rt>y</rt></ruby>',
      );
      final tree = _tree(parsed.group);
      final cache = _cache();
      try {
        final metrics = _measure(tree, cache);
        final id = tree.nodes.indexWhere((n) => n is ForumBodyRubyTreeFrame);
        final frame = metrics.nodes[id] as ForumBodyRubyTreeContainerMetrics;
        final child = tree.nodes[id] as ForumBodyRubyTreeFrame;
        expect(child.input.source, isNotNull);
        expect(frame.font.height, 120);
        // RB background already belongs to the inherited native text highlight
        // under the current resolver. Do not add a second alpha surface.
        expect(frame.backgroundFont, isNull);
        expect(child.background, isNull);
        expect(child.input.style.ownBackground, const Color(0x80ff0000));
        expect(frame.frame.size.height, 120);
        expect(metrics.nodes[child.child].box!.bounds.height, 30);
        expect(frame.frame.childTop, greaterThan(0));
        expect(
          (tree.nodes.first as ForumBodyRubyTreeText)
              .content
              .style
              .textStyle
              .backgroundColor,
          const Color(0x80ff0000),
        );
      } finally {
        cache.close();
      }
    },
  );

  test('implicit frame does not duplicate its root background', () {
    final tree = _tree(
      _Parsed(
        '<ruby style="background:rgba(255,0,0,0.5)">'
        '<ruby>A<rt>x</rt></ruby><rt>y</rt></ruby>',
      ).group,
    );
    final frame = tree.nodes.whereType<ForumBodyRubyTreeFrame>().single;
    expect(frame.input.source, isNull);
    expect(frame.background, isNull);
    expect(
      tree.nodes.whereType<ForumBodyRubyTreeContainer>().where(
        (n) => n.background != null,
      ),
      hasLength(1),
    );
  });

  test(
    'external pressure waits for budget revision and resumes the same tree',
    () {
      final cache = _cache(entries: 1);
      final tree = _tree(_Parsed(_nested).group);
      final foreign = _tree(_Parsed('<ruby>Z<rt>z</rt></ruby>').group);
      final pinned = cache.acquire(
        content: (foreign.nodes.first as ForumBodyRubyTreeText).content,
        width: 500,
      );
      final work = ForumBodyRubyTreeMetricsPreparation(
        input: tree,
        cache: cache,
        ensureOwner: () {},
      );
      try {
        final first = work.advance();
        expect(first.waitingForLayoutBudget, isTrue);
        final builds = cache.layoutBuildCount;
        final again = work.advance();
        expect(again.formatUnitsPrepared, 0);
        expect(again.waitingForLayoutBudget, isTrue);
        expect(cache.layoutBuildCount, builds);
        pinned.release();
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
        expect(work.takeMetrics().box.bounds.size, const Size(48, 38));
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        pinned.release();
        cache.close();
      }
    },
  );

  test(
    'scaling uses actual nested native fonts and snapshots survive owner retirement',
    () {
      final tree = _tree(_Parsed(_nested).group);
      final cache = _cache();
      final metrics = _measure(tree, cache, scaler: TextScaler.linear(1.5));
      expect(metrics.box.bounds.size, const Size(72, 57));
      cache.close();
      expect(metrics.box.bounds.size, const Size(72, 57));
      expect(() => metrics.nodes.clear(), throwsUnsupportedError);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'owner cancellation and reentrant close cannot leave pending native leases',
    () {
      final tree = _tree(_Parsed(_nested).group);
      for (final guardCall in [1, 2, 3, 5, 9, 15]) {
        final cache = _cache();
        var calls = 0;
        late final ForumBodyRubyTreeMetricsPreparation work;
        work = ForumBodyRubyTreeMetricsPreparation(
          input: tree,
          cache: cache,
          ensureOwner: () {
            if (++calls == guardCall) work.close();
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
          expect(() => work.advance(), throwsStateError);
        } finally {
          work.close();
          cache.close();
        }
      }
    },
  );

  test(
    'native child capture rejects foreign, substituted and retired leaves',
    () {
      final first = _cache();
      final second = _cache();
      final tree = _tree(_Parsed(_nested).group);
      final texts = tree.nodes.whereType<ForumBodyRubyTreeText>().toList();
      final lease = first.acquire(content: texts.first.content, width: 500);
      try {
        expect(
          () => ForumBodyRubyChildMetrics.measure(
            cache: second,
            lease: lease,
            content: texts.first.content,
          ),
          throwsStateError,
        );
        expect(
          () => ForumBodyRubyChildMetrics.measure(
            cache: first,
            lease: lease,
            content: texts.last.content,
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
        lease.release();
        expect(
          () => ForumBodyRubyChildMetrics.measure(
            cache: first,
            lease: lease,
            content: texts.first.content,
          ),
          throwsStateError,
        );
      } finally {
        lease.release();
        first.close();
        second.close();
      }
    },
  );

  test('a stale nested font or style scope is rejected before native work', () {
    final parsed = _Parsed(_nested);
    final rb = parsed.group.base.single as ForumBodyRubyBaseContent;
    final nested = rb.parts.single as ForumBodyRubyNestedContent;
    final original = nested.groups.single;
    for (final staleFont in [false, true]) {
      final stale = ForumBodyRubyGroupContent(
        identity: original.identity,
        fontRevision: staleFont ? 'retired-font' : original.fontRevision,
        styleRevision: staleFont
            ? original.styleRevision
            : original.styleRevision + 1,
        style: original.style,
        rootPath: original.rootPath,
        index: original.index,
        base: original.base,
        annotations: original.annotations,
      );
      final root = ForumBodyRubyGroupContent(
        identity: parsed.group.identity,
        fontRevision: parsed.group.fontRevision,
        styleRevision: parsed.group.styleRevision,
        style: parsed.group.style,
        rootPath: parsed.group.rootPath,
        index: parsed.group.index,
        base: [
          ForumBodyRubyBaseContent(
            path: rb.path,
            source: rb.source,
            style: rb.style,
            parts: [
              ForumBodyRubyNestedContent(
                path: nested.path,
                source: nested.source,
                style: nested.style,
                groups: [stale],
              ),
            ],
          ),
        ],
        annotations: parsed.group.annotations,
      );
      expect(
        () => _tree(root),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
    }
  });

  test(
    'retirement from a native scaler callback cannot retain a late shape',
    () {
      final tree = _tree(_Parsed(_nested).group);
      for (final closeCache in [false, true]) {
        final cache = _cache();
        late final ForumBodyRubyTreeMetricsPreparation work;
        var armed = true;
        work = ForumBodyRubyTreeMetricsPreparation(
          input: tree,
          cache: cache,
          ensureOwner: () {},
          textScaler: _CallbackScaler(() {
            if (armed) {
              armed = false;
              if (closeCache) {
                cache.close();
              } else {
                work.close();
              }
            }
          }),
        );
        try {
          expect(() => work.advance(), throwsStateError);
          expect(work.nativeLeases, isEmpty);
          expect(cache.activeLeases, 0);
          expect(work.isReady, isFalse);
        } finally {
          work.close();
          cache.close();
        }
      }
    },
  );
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final void Function() callback;
  @override
  double scale(double fontSize) {
    callback();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
