import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_layer_fixture.dart';

Future<List<int>> _pixels(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(200, 180);
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
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 16,
      maxEstimatedBytes: 1 << 23,
    ),
  );
  tearDown(() => cache.close());

  for (var mode = 0; mode < 5; mode++) {
    test(
      'three RTC ranks match independent native paint and source hits, mode=$mode',
      () async {
        final input = rubyLayerInput(lineHeight: mode == 4 ? .25 : 1);
        final scaler = mode == 4
            ? TextScaler.linear(1.27)
            : TextScaler.noScaling;
        final sides = [
          for (var i = 0; i < 3; i++)
            mode == 1
                ? ForumBodyRubySide.over
                : mode == 2
                ? ForumBodyRubySide.under
                : (i.isEven != (mode == 3)
                      ? ForumBodyRubySide.over
                      : ForumBodyRubySide.under),
        ];
        final group = rubyLayerGroup(
          cache: cache,
          parts: input.parts,
          sides: sides,
          gaps: [1, 2, 3],
          textScaler: scaler,
        );
        final painters = <TextPainter>[];
        try {
          for (final part in input.parts) {
            painters.add(
              TextPainter(
                text: part.textSpan,
                textDirection: part.style.textDirection,
                textScaler: scaler,
              )..layout(),
            );
          }
          final bounds = [
            for (final (index, painter) in painters.indexed)
              painter
                  .getBoxesForSelection(
                    TextSelection(
                      baseOffset: 0,
                      extentOffset: input.parts[index].projection.text.length,
                    ),
                  )
                  .fold(
                    Rect.fromLTWH(0, 0, painter.width, painter.height),
                    (rect, box) => rect.expandToInclude(box.toRect()),
                  ),
          ];
          final width = bounds.map((rect) => rect.width).reduce(math.max);
          var over = 0.0;
          var under = 0.0;
          for (var i = 0; i < 3; i++) {
            if (sides[i] == ForumBodyRubySide.over) {
              over += bounds[i + 1].height + i + 1;
            } else {
              under += bounds[i + 1].height + i + 1;
            }
          }
          expect(group.size.width, closeTo(width, 1e-4));
          expect(
            group.size.height,
            closeTo(over + bounds[0].height + under, 1e-4),
          );
          final origins = [
            Offset(
              (width - bounds[0].width) / 2 - bounds[0].left,
              over - bounds[0].top,
            ),
          ];
          var top = over;
          var bottom = over + bounds[0].height;
          for (var i = 0; i < 3; i++) {
            final rect = bounds[i + 1];
            final double y;
            if (sides[i] == ForumBodyRubySide.over) {
              top -= rect.height + i + 1;
              y = top;
            } else {
              y = bottom + i + 1;
              bottom = y + rect.height;
            }
            origins.add(
              Offset((width - rect.width) / 2 - rect.left, y - rect.top),
            );
          }
          final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          );
          const offset = Offset(3.25, 4.5);
          final actual = await _pixels((canvas) => group.paint(canvas, offset));
          final expected = await _pixels((canvas) {
            for (var i = 0; i < painters.length; i++) {
              painters[i].paint(canvas, offset + origins[i]);
            }
          });
          expect(actual, expected);
          expect(actual.any((value) => value != 0), isTrue);
          final handles = group.nativeLeases
              .cast<ForumBodyTextLease>()
              .toList();
          expect(handles.length, 4);
          for (var index = 0; index < input.parts.length; index++) {
            final part = index == 0
                ? ForumBodyRubyPart.base
                : ForumBodyRubyPart.annotation;
            final rank = index == 0 ? null : index - 1;
            final boxes = group.selectionBoxes(
              part: part,
              annotationIndex: rank,
              startUtf16: 0,
              endUtf16: input.parts[index].projection.text.length,
            );
            final box = boxes.first.toRect();
            final point = Offset(box.left + .1, box.center.dy);
            final hit = group.sourceAt(point);
            final native = handles[index].layout.sourceAt(
              point - origins[index],
            );
            expect(hit.part, part);
            expect(hit.annotationIndex, rank);
            expect(hit.position.sourceRune, native.sourceRune);
            expect(hit.position.displayUtf16, native.displayUtf16);
            expect(hit.position.isExact, isTrue);
            expect(
              identical(
                group.contentFor(part, annotationIndex: rank),
                input.parts[index],
              ),
              isTrue,
            );
          }
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          ), before);
          expect(before, (1, 1, 4));
        } finally {
          for (final painter in painters) {
            painter.dispose();
          }
          group.close();
        }
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'outer-only RT reports original rank and empty-base hits stay approximate',
    () {
      final input = rubyLayerInput(
        base: '',
        annotations: const [('', 10), ('', 15), ('qq', 5)],
      );
      final group = rubyLayerGroup(cache: cache, parts: input.parts);
      try {
        expect(group.annotationCount, 3);
        expect(group.nativeLeases.length, 2);
        final box = group
            .selectionBoxes(
              part: ForumBodyRubyPart.annotation,
              annotationIndex: 2,
              startUtf16: 0,
              endUtf16: 1,
            )
            .single
            .toRect();
        final hit = group.sourceAt(Offset(box.left + .1, box.center.dy));
        expect(hit.annotationIndex, 2);
        expect(hit.position.isExact, isTrue);
        final blank = group.sourceAt(
          Offset(
            1,
            (group.metrics.baseBandTop + group.metrics.baseBandBottom) / 2,
          ),
        );
        expect(blank.part, ForumBodyRubyPart.annotation);
        expect(blank.annotationIndex, 2);
        expect(blank.position.isExact, isFalse);
        expect(
          group.selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            annotationIndex: 0,
            startUtf16: 0,
            endUtf16: 0,
          ),
          isEmpty,
        );
        expect(
          () => group.contentFor(ForumBodyRubyPart.annotation),
          throwsStateError,
        );
        expect(
          () => group.selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            startUtf16: 0,
            endUtf16: 1,
          ),
          throwsStateError,
        );
        expect(
          () => group.projectionFor(
            ForumBodyRubyPart.annotation,
            annotationIndex: 3,
          ),
          throwsRangeError,
        );
        expect(
          () => group.contentFor(ForumBodyRubyPart.base, annotationIndex: 0),
          throwsArgumentError,
        );
      } finally {
        group.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'cached partial misses release only their aliases and never shape an outer layer',
    () {
      final input = rubyLayerInput();
      final aliases = [
        for (final part in input.parts.take(3))
          cache.acquire(content: part, width: 300),
      ];
      addTearDown(() {
        for (final alias in aliases) {
          alias.release();
        }
      });
      final layers = [
        for (final (rank, part) in input.parts.skip(1).indexed)
          (
            content: part,
            gap: 0.0,
            side: rank.isEven
                ? ForumBodyRubySide.over
                : ForumBodyRubySide.under,
          ),
      ];
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      expect(
        ForumBodyRubyGroupLayout.tryCreateCachedLayers(
          cache: cache,
          base: input.parts.first,
          annotations: layers,
          maxWidth: 300,
        ),
        isNull,
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      aliases.add(cache.acquire(content: input.parts.last, width: 300));
      final ready = ForumBodyRubyGroupLayout.tryCreateCachedLayers(
        cache: cache,
        base: input.parts.first,
        annotations: layers,
        maxWidth: 300,
      )!;
      expect(cache.activeLeases, 8);
      expect(ready.nativeLeases.length, 4);
      ready.close();
      expect(cache.activeLeases, 4);
      expect(aliases.every((alias) => alias.isActive), isTrue);
    },
  );

  test(
    'duplicate handles and unprepared outer pictures fail adoption without retiring witnesses',
    () {
      final input = rubyLayerInput();
      final band = ForumBodyTextBandContent(contexts: input.parts);
      final witnesses = [
        for (var i = 0; i < 4; i++)
          cache.acquireBandChild(content: band, childIndex: i),
      ];
      addTearDown(() {
        for (final lease in witnesses) {
          lease.release();
        }
      });
      for (final duplicate in [true, false]) {
        final handles = [
          for (var i = 0; i < 4; i++)
            cache.acquireBandChild(content: band, childIndex: i),
        ];
        if (duplicate) handles[1].release();
        expect(
          () => ForumBodyRubyGroupLayout.adoptLayers(
            cache: cache,
            baseLease: handles[0],
            annotations: [
              for (var i = 1; i < 4; i++)
                (
                  content: input.parts[i],
                  lease: duplicate && i == 1 ? handles[0] : handles[i],
                  gap: 0.0,
                  side: ForumBodyRubySide.over,
                ),
            ],
          ),
          throwsStateError,
        );
        expect(handles.any((handle) => handle.isActive), isFalse);
        expect(witnesses.every((lease) => lease.isActive), isTrue);
        expect(cache.activeLeases, 4);
      }
    },
  );

  test(
    'level adoption aligns each rank and all shared base hit boundaries',
    () {
      final large = rubyLayerInput(
        base: '<span style="font-size:30px">A</span>',
        annotations: const [('x', 10), ('y', 15), ('z', 5)],
      );
      final small = rubyLayerInput(
        base: 'B',
        annotations: const [('a', 15), ('b', 5), ('c', 10)],
      );
      final first = rubyLayerGroup(
        cache: cache,
        parts: large.parts,
        gaps: [1, 2, 3],
      );
      final second = rubyLayerGroup(
        cache: cache,
        parts: small.parts,
        gaps: [1, 2, 3],
      );
      final level = ForumBodyRubyLevelMetrics.single(
        first.metrics,
      ).include(second.metrics);
      first.close();
      second.close();
      final a = rubyLayerGroup(
        cache: cache,
        parts: large.parts,
        gaps: [1, 2, 3],
        level: level,
      );
      final b = rubyLayerGroup(
        cache: cache,
        parts: small.parts,
        gaps: [1, 2, 3],
        level: level,
      );
      try {
        expect(a.baseline, b.baseline);
        expect(a.metrics.baseBandTop, b.metrics.baseBandTop);
        expect(a.metrics.baseBandBottom, b.metrics.baseBandBottom);
        final baseTop = b.metrics.baseBandTop;
        final middle = (baseTop + b.metrics.annotations[0].bandBottom) / 2;
        expect(
          b.sourceAt(Offset(b.size.width / 2, middle)).part,
          ForumBodyRubyPart.base,
        );
        expect(
          b.sourceAt(Offset(b.size.width / 2, middle - .001)).annotationIndex,
          0,
        );
        for (var i = 0; i < 3; i++) {
          final x = a.metrics.annotations[i];
          final y = b.metrics.annotations[i];
          expect(x.offset.dy + x.fontBaseline, y.offset.dy + y.fontBaseline);
        }
      } finally {
        a.close();
        b.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'owner retirement invalidates every layer before hit, paint or selection',
    () {
      final input = rubyLayerInput();
      final group = rubyLayerGroup(cache: cache, parts: input.parts);
      cache.close();
      expect(group.isActive, isFalse);
      expect(() => group.sourceAt(Offset.zero), throwsStateError);
      expect(
        () => group.selectionBoxes(
          part: ForumBodyRubyPart.annotation,
          annotationIndex: 2,
          startUtf16: 0,
          endUtf16: 1,
        ),
        throwsStateError,
      );
      group.close();
      group.close();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'cold acquisition snapshots ranks before TextScaler callbacks mutate the caller list',
    () {
      final input = rubyLayerInput();
      final layers = [
        for (final (rank, part) in input.parts.skip(1).indexed)
          (
            content: part,
            gap: 0.0,
            side: rank.isEven
                ? ForumBodyRubySide.over
                : ForumBodyRubySide.under,
          ),
      ];
      var mutated = false;
      final group = ForumBodyRubyGroupLayout.createLayers(
        cache: cache,
        base: input.parts.first,
        annotations: layers,
        textScaler: _MutatingScaler(() {
          if (!mutated) {
            mutated = true;
            layers.clear();
          }
        }),
      );
      try {
        expect(mutated, isTrue);
        expect(layers, isEmpty);
        expect(group.annotationCount, 3);
        expect(group.nativeLeases.length, 4);
        expect(
          group.contentFor(ForumBodyRubyPart.annotation, annotationIndex: 2),
          same(input.parts[3]),
        );
      } finally {
        group.close();
      }
      expect(cache.activeLeases, 0);
    },
  );
}

final class _MutatingScaler extends TextScaler {
  const _MutatingScaler(this.onScale);
  final void Function() onScale;
  @override
  double scale(double fontSize) {
    onScale();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
