import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_child_input.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_inline_page_preparation.dart';

({ForumBodyInlineFlowContent outer, ForumBodyRubySequenceChildInput child})
_child(
  String content, {
  bool annotation = false,
  String direction = 'ltr',
  String style = '',
}) {
  final doc = const ForumBodyParser().parse(
    html: annotation
        ? '<ruby dir="$direction">Z<rt style="$style">$content</rt></ruby>'
        : '<ruby dir="$direction"><rb style="$style">$content</rb><rt>z</rt></ruby>',
    sourceId: 'intrinsic-ruby-child',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'intrinsic-ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        final group = content.parts
            .whereType<ForumBodyInlineFlowRuby>()
            .single
            .group;
        return (
          outer: content,
          child:
              (annotation
                      ? ForumBodyRubyChildInput.annotation(
                          group,
                          group.annotations.single
                              as ForumBodyRubyTextAnnotationContent,
                        )
                      : ForumBodyRubyChildInput.base(
                          group,
                          group.base.single as ForumBodyRubyBaseContent,
                        ))
                  as ForumBodyRubySequenceChildInput,
        );
      }
    }
    throw StateError('Missing actual child IR');
  } finally {
    cursor.close();
  }
}

ForumBodyParagraphCache _cache() =>
    ForumBodyParagraphCache(maxEntries: 64, maxEstimatedBytes: 1 << 24);

({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
_plan(
  ForumBodyInlineFlowContent flow,
  ForumBodyParagraphCache cache, {
  double width = 30,
  TextScaler scaler = TextScaler.noScaling,
  int quantum = 1,
}) {
  final work = ForumBodyInlinePlanPreparation.fromFlow(
    input: flow,
    width: width,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    for (var i = 0; !work.isReady && i < 10000; i++) {
      final builds = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      final step = work.advance(maxParts: quantum);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
      expect(cache.pictureBuildCount, pictures);
    }
    expect(work.isReady, isTrue);
    return work.take();
  } finally {
    work.close();
  }
}

ForumBodyInlineParagraphView _view(
  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  plan,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
}) {
  final composer = ForumBodyTextPageComposer(
    identity: plan.content.identity,
    layoutId: 'actual-intrinsic-child',
    width: plan.lease.layout.width,
    height: 1000,
    maxPages: 2,
    maxFragments: 2,
    maxNativeHandlesPerPage: 512,
  );
  late ForumBodyTextPageFragment fragment;
  try {
    composer.appendInline(
      lease: plan.lease,
      paragraphIndex: 0,
      left: 0,
      spaceBefore: 0,
      spaceAtPageStart: 0,
      nativeHandleCountInRange: plan.content.nativeHandleCountInRange,
    );
    while (!composer.needsInput) {
      composer.advance(maxLines: 1);
    }
    composer.finish();
    fragment = composer.snapshot[0].fragments.single;
  } finally {
    composer.close();
  }
  final work = ForumBodyInlinePagePreparation(
    input: plan.content,
    fragment: fragment,
    identity: plan.content.identity,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
    ownedPageLeases: () => const [],
  );
  try {
    for (var i = 0; i < 10000; i++) {
      final builds = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      final step = work.advance(cachedOnly: false, maxParts: 1);
      expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
      expect(cache.pictureBuildCount - pictures, lessThanOrEqualTo(1));
      expect(step.cacheMiss, isFalse);
      if (step.view != null) return step.view!;
    }
    throw StateError('Child binding did not finish');
  } finally {
    work.close();
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
    'actual child adapter retains contexts, groups and explicit edge policy',
    () {
      final parsed = _child(' L <ruby>A<rt>x</rt>B<rt>y</rt></ruby> R ');
      final child = parsed.child;
      for (final trim in [false, true]) {
        final flow = child.toInlineFlow(trimCollapsibleEdges: trim);
        expect(flow.identity, child.identity);
        expect(flow.path, child.path);
        expect(flow.style, same(child.style));
        expect(
          flow.layoutMode,
          ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        );
        expect(flow.appliesFirstLineIndent, isFalse);
        expect(flow.trimCollapsibleEdges, trim);
        final nested = child.parts[1] as ForumBodyRubyNestedContent;
        expect(flow.parts, hasLength(4));
        expect(
          (flow.parts.first as ForumBodyInlineFlowText).content,
          same((child.parts.first as ForumBodyRubyTextContent).content),
        );
        expect(
          flow.parts.whereType<ForumBodyInlineFlowRuby>().map((p) => p.group),
          orderedEquals(nested.groups),
        );
        final input = ForumBodyInlinePlanInput(flow, 100);
        expect(
          input.content.projection.display.text,
          trim ? 'L AxBy R' : ' L AxBy R ',
        );
      }
      // Standalone child support does not bypass the outer tree's missing mixed
      // native footprint/source transaction or broaden Session's capability.
      expect(
        () => ForumBodyInlinePlanInput(parsed.outer, 100),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  for (final direction in ['ltr', 'rtl']) {
    for (final annotation in [false, true]) {
      for (final scaled in [false, true]) {
        test(
          'real intrinsic parent and readable child direction=$direction RT=$annotation scaled=$scaled',
          () async {
            final child = _child(
              'L<ruby>A<rt>x</rt></ruby>R',
              direction: direction,
              annotation: annotation,
              style: 'font-size:20px;line-height:.25;text-indent:2em',
            ).child;
            final cache = _cache();
            addTearDown(cache.close);
            final scaler = scaled
                ? const _NonlinearScaler()
                : TextScaler.noScaling;
            final flow = child.toInlineFlow(trimCollapsibleEdges: annotation);
            final result = _plan(
              flow,
              cache,
              scaler: scaler,
              quantum: scaled ? 7 : 1,
            );
            expect(
              result.content.layoutMode,
              ForumBodyParagraphLayoutMode.intrinsicSingleLine,
            );
            final layout = result.lease.layout;
            expect(layout.lines, hasLength(1));
            expect(layout.width, greaterThan(30));
            expect(layout.firstLineIndent.appliedAdvance, 0);
            expect(layout.projection.enginePrefix, isEmpty);
            expect(layout.projection.engineText, 'L\ufffcR');
            expect(result.content.content.projection.display.text, 'LAxR');
            expect(layout.dimensions.single.size.width, scaled ? 27 : 20);
            final width = layout.width;
            final height = layout.height;
            final view = _view(result, cache, scaler: scaler);
            try {
              expect(view.width, width);
              expect(view.height, height);
              final builds = cache.layoutBuildCount;
              final pictures = cache.pictureBuildCount;
              for (var i = 0; i < 4; i++) {
                final boxes = view.glyphBoxes(i, i + 1);
                expect(boxes, isNotEmpty, reason: 'source window $i');
                final box = boxes.single;
                expect(box.top, greaterThanOrEqualTo(-1e-3));
                expect(box.bottom, lessThanOrEqualTo(view.height + 1e-3));
                final point = Offset(
                  box.left +
                      (box.right - box.left) *
                          (box.direction == TextDirection.ltr ? .2 : .8),
                  (box.top + box.bottom) / 2,
                );
                final hit = view.sourceAt(point);
                expect(hit.isExact, isTrue);
                expect(hit.displayUtf16, i);
                expect(
                  hit.sourceRune,
                  view.content.projection.display.sourceAtUtf16(i).sourceRune,
                );
              }
              for (final dpr in [1.0, 3.0]) {
                final recorder = ui.PictureRecorder();
                view.paint(Canvas(recorder)..scale(dpr), Offset.zero);
                final picture = recorder.endRecording();
                final pixelWidth = (width * dpr).ceil();
                final pixelHeight = (height * dpr).ceil();
                final image = await picture.toImage(pixelWidth, pixelHeight);
                try {
                  final rgba = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List();
                  for (var i = 0; i < 4; i++) {
                    expect(
                      _hasInk(
                        rgba,
                        pixelWidth,
                        pixelHeight,
                        view.glyphBoxes(i, i + 1).single.toRect(),
                        dpr,
                      ),
                      isTrue,
                      reason: 'actual painted source window $i DPR$dpr',
                    );
                  }
                } finally {
                  image.dispose();
                  picture.dispose();
                }
              }
              expect(cache.layoutBuildCount, builds);
              expect(cache.pictureBuildCount, pictures);
            } finally {
              view.close();
            }
            expect(cache.activeLeases, 0);
            cache.clearUnpinned();
            expect(cache.estimatedRetainedBytes, 0);
          },
        );
      }
    }
  }

  test(
    'intrinsic parent stays intrinsic through real same-root spanning alignment',
    () {
      final child = _child(
        'LL<ruby><rb>A</rb><rb>B</rb><rtc>wide</rtc></ruby>RR',
      ).child;
      final cache = _cache();
      addTearDown(cache.close);
      final result = _plan(
        child.toInlineFlow(trimCollapsibleEdges: false),
        cache,
        width: 80,
      );
      expect(result.content.rubyAtoms.single, isA<ForumBodyRubySegmentPlan>());
      expect(result.lease.layout.lines, hasLength(1));
      expect(result.lease.layout.width, greaterThan(80));
      final view = _view(result, cache);
      try {
        expect(view.content.projection.display.text, 'LLABwideRR');
        for (var i = 0; i < view.content.projection.display.text.length; i++) {
          expect(view.glyphBoxes(i, i + 1), isNotEmpty);
        }
      } finally {
        view.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  for (final direction in ['ltr', 'rtl']) {
    test(
      'intrinsic final parent retains actual layer SPACE direction=$direction',
      () {
        final child = _child(
          'L<ruby><rb>A</rb><rb>B</rb>'
          '<rtc><rt>x</rt> <rt>y</rt></rtc></ruby>R',
          direction: direction,
        ).child;
        final cache = _cache();
        addTearDown(cache.close);
        final result = _plan(
          child.toInlineFlow(trimCollapsibleEdges: false),
          cache,
        );
        expect(
          result.content.content.projection.atoms.where((a) => a.isSoftSpace),
          hasLength(1),
        );
        expect(result.content.trimmedAtomIndices, isEmpty);
        expect(result.lease.layout.lines, hasLength(1));
        final view = _view(result, cache);
        try {
          final display = view.content.projection.display.text;
          expect(display, 'LAx ByR');
          expect(
            view.content.projection.display
                .sourceAtUtf16(display.indexOf('B'))
                .sourceRune,
            lessThan(
              view.content.projection.display
                  .sourceAtUtf16(display.indexOf('x'))
                  .sourceRune,
            ),
          );
          for (var i = 0; i < display.length; i++) {
            expect(view.glyphBoxes(i, i + 1), isNotEmpty);
          }
        } finally {
          view.close();
        }
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'mode-aware native offsets exclude reader indent during child row alignment',
    () {
      final original = _child(
        'L<ruby>A<rt>x</rt>B<rt>y</rt></ruby>R',
        style: 'text-indent:2em',
      ).child.toInlineFlow(trimCollapsibleEdges: false);
      final flow = ForumBodyInlineFlowContent(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        layoutMode: original.layoutMode,
        // Exercise mode handling even when the caller has a reader-indent flag.
        appliesFirstLineIndent: true,
        parts: original.parts,
        ignored: original.ignored,
        issues: original.issues,
      );
      final input = ForumBodyInlinePlanInput(flow, 30);
      expect(input.atomEngineOffsets, [1, 2]);
      expect(
        input.content
            .projectionForLayout(ForumBodyParagraphLayoutMode.wrap)
            .atoms
            .first
            .engineUtf16,
        greaterThan(1),
      );
      final cache = _cache();
      addTearDown(cache.close);
      final result = _plan(flow, cache);
      try {
        expect(result.lease.layout.lines, hasLength(1));
        expect(result.lease.layout.firstLineIndent.appliedAdvance, 0);
        expect(result.lease.layout.projection.enginePrefix, isEmpty);
      } finally {
        result.lease.release();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'retirement during intrinsic native scale callbacks releases pending work',
    () {
      final cache = _cache();
      addTearDown(cache.close);
      late ForumBodyInlinePlanPreparation work;
      var retired = false;
      var callbackCount = 0;
      work = ForumBodyInlinePlanPreparation.fromFlow(
        input: _child(
          'L<ruby>A<rt>x</rt></ruby>R',
        ).child.toInlineFlow(trimCollapsibleEdges: false),
        width: 30,
        cache: cache,
        textScaler: _CallbackScaler(() {
          callbackCount++;
          retired = true;
          work.close();
        }),
        ensureOwner: () {
          if (retired) throw StateError('retired test owner');
        },
      );
      addTearDown(work.close);
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsStateError);
      expect(callbackCount, greaterThan(0));
      expect(cache.activeLeases, 0);
      cache.clearUnpinned();
      expect(cache.estimatedRetainedBytes, 0);
      expect(() => work.take(), throwsStateError);
    },
  );

  test('empty nested roots and fit mode are explicit unsupported inputs', () {
    final child = _child('L<ruby></ruby>R').child;
    expect(
      () => child.toInlineFlow(trimCollapsibleEdges: false),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    final flow = _child(
      'L<ruby>A<rt>x</rt></ruby>R',
    ).child.toInlineFlow(trimCollapsibleEdges: false);
    final fit = ForumBodyInlineFlowContent(
      identity: flow.identity,
      path: flow.path,
      fontRevision: flow.fontRevision,
      styleRevision: flow.styleRevision,
      style: flow.style,
      layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      parts: flow.parts,
      ignored: flow.ignored,
      issues: flow.issues,
    );
    expect(
      () => ForumBodyInlinePlanInput(fit, 100),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
  });
}

bool _hasInk(List<int> rgba, int width, int height, Rect box, double dpr) {
  final left = (box.left * dpr).floor().clamp(0, width);
  final right = (box.right * dpr).ceil().clamp(0, width);
  final top = (box.top * dpr).floor().clamp(0, height);
  final bottom = (box.bottom * dpr).ceil().clamp(0, height);
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      if (rgba[(y * width + x) * 4 + 3] > 0) return true;
    }
  }
  return false;
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize >= 20 ? 1.35 : 1.1);
  @override
  double get textScaleFactor => 1;
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.onScale);
  final void Function() onScale;
  @override
  double scale(double fontSize) {
    onScale();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
