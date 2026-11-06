import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_layer_fixture.dart';

typedef _Input = ({
  List<ForumBodyParagraphContent> parts,
  List<ForumBodyTextRequest> requests,
});

_Input _input({int ranks = 100, bool missing = false, bool emptyBase = false}) {
  final input = rubyLayerInput(
    base: emptyBase ? '' : 'AB',
    annotations: [
      for (var i = 0; i < ranks; i++)
        (missing && i % 17 != 0 ? '' : 'r$i', 1.0),
    ],
  );
  final glyphs = input.parts
      .where((part) => part.projection.text.isNotEmpty)
      .toList();
  final requests =
      Map<ForumBodyParagraphContent, ForumBodyTextRequest>.identity();
  for (var start = 0; start < glyphs.length; start += 64) {
    final band = ForumBodyTextBandContent(
      contexts: glyphs.sublist(start, (start + 64).clamp(0, glyphs.length)),
    );
    for (var i = 0; i < band.contexts.length; i++) {
      requests[band.contexts[i]] = ForumBodyTextRequest.bandChild(
        band: band,
        childIndex: i,
      );
    }
  }
  return (
    parts: input.parts,
    requests: [
      for (final part in input.parts)
        requests[part] ?? ForumBodyTextRequest.paragraph(part),
    ],
  );
}

ForumBodyRubyGroupPreparation _open(
  ForumBodyParagraphCache cache,
  _Input input, {
  bool metrics = false,
  void Function()? ensureOwner,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final annotations = [
    for (final (rank, request) in input.requests.skip(1).indexed)
      (
        request: request,
        gap: 0.0,
        side: rank.isEven ? ForumBodyRubySide.over : ForumBodyRubySide.under,
      ),
  ];
  final prepare = metrics
      ? ForumBodyRubyGroupPreparation.forLayerMetrics(
          cache: cache,
          base: input.requests.first,
          annotations: annotations,
          ensureOwner: ensureOwner ?? () {},
          textScaler: textScaler,
        )
      : ForumBodyRubyGroupPreparation.fromLayerRequests(
          cache: cache,
          base: input.requests.first,
          annotations: annotations,
          ensureOwner: ensureOwner ?? () {},
          textScaler: textScaler,
        );
  addTearDown(prepare.close);
  return prepare;
}

void _finish(ForumBodyRubyGroupPreparation prepare, {int quantum = 32}) {
  for (var i = 0; !prepare.isReady && i < 20000; i++) {
    final before = prepare.workCount;
    final step = prepare.advance(maxParts: quantum);
    expect(step.formatUnitsPrepared, inInclusiveRange(0, quantum));
    expect(step.partsInspected, lessThanOrEqualTo(quantum));
    expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
    expect(prepare.workCount - before, step.formatUnitsPrepared);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
  }
  expect(prepare.isReady, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 24,
    ),
  );
  tearDown(() => cache.close());

  for (final quantum in [1, 7, 32]) {
    for (final metrics in [false, true]) {
      test(
        '100 ranks keep acquisition, positioning and native work bounded, q=$quantum metrics=$metrics',
        () {
          final input = _input();
          final prepare = _open(cache, input, metrics: metrics);
          _finish(prepare, quantum: quantum);
          expect(prepare.expectedPartCount, 101);
          expect(prepare.preparedPartCount, 101);
          expect(cache.layoutBuildCount, 2);
          if (metrics) {
            expect(cache.pictureBuildCount, 0);
            expect(cache.activeLeases, 0);
            expect(prepare.nativeLeases, isEmpty);
            final result = prepare.takeMetrics();
            expect(result.annotations.length, 100);
            // Independent native band rows accumulate small font-edge float
            // errors. Keep their real bounds, within per-rank geometry precision.
            expect(
              result.size.height,
              closeTo(
                120,
                input.parts.length *
                    ForumBodyRubyGroupMetrics.geometryTolerance,
              ),
            );
            cache.close();
            expect(result.annotations[99].hasAnnotation, isTrue);
          } else {
            final group = prepare.takeLayout();
            try {
              expect(group.annotationCount, 100);
              expect(group.nativeLeases.length, 101);
              expect(cache.pictureBuildCount, 2);
              expect(
                group.size.height,
                closeTo(
                  120,
                  input.parts.length *
                      ForumBodyRubyGroupMetrics.geometryTolerance,
                ),
              );
              final box = group
                  .selectionBoxes(
                    part: ForumBodyRubyPart.annotation,
                    annotationIndex: 99,
                    startUtf16: 0,
                    endUtf16: 1,
                  )
                  .single
                  .toRect();
              expect(
                group
                    .sourceAt(Offset(box.left + .1, box.center.dy))
                    .annotationIndex,
                99,
              );
            } finally {
              group.close();
            }
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }

  test(
    'empty ranks still count numeric work without acquiring native handles',
    () {
      final input = _input(missing: true, emptyBase: true);
      final prepare = _open(cache, input);
      _finish(prepare, quantum: 1);
      expect(prepare.preparedPartCount, 7);
      final group = prepare.takeLayout();
      try {
        expect(group.annotationCount, 100);
        expect(group.nativeLeases.length, 7);
        expect(group.metrics.annotations[98].hasAnnotation, isFalse);
        expect(group.metrics.annotations[85].hasAnnotation, isTrue);
        expect(
          group.selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            annotationIndex: 98,
            startUtf16: 0,
            endUtf16: 0,
          ),
          isEmpty,
        );
      } finally {
        group.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'cache-only metrics scan and numeric finalization yield even on complete warm hits',
    () {
      final input = _input();
      for (final request in input.requests) {
        request
            .acquire(
              cache,
              width: 16384,
              textScaler: TextScaler.noScaling,
              cachedOnly: false,
            )!
            .release();
      }
      final builds = cache.layoutBuildCount;
      final prepare = _open(cache, input, metrics: true);
      var quanta = 0;
      while (!prepare.isReady && quanta++ < 1000) {
        final before = prepare.workCount;
        prepare.tryPrepareCached(maxParts: 7);
        expect(prepare.cacheMiss, isFalse);
        expect(prepare.workCount - before, inInclusiveRange(1, 7));
        expect(cache.layoutBuildCount, builds);
        expect(cache.pictureBuildCount, 0);
      }
      expect(quanta, greaterThan(20));
      expect(prepare.isReady, isTrue);
      expect(cache.activeLeases, 0);
      prepare.takeMetrics();
    },
  );

  test(
    'cache-only readable miss records no picture and resumes the same pending child',
    () {
      final input = _input();
      final external = input.requests.first.acquire(
        cache,
        width: 16384,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      addTearDown(external.release);
      final prepare = _open(cache, input);
      expect(prepare.tryPrepareCached(maxParts: 7), isFalse);
      expect(prepare.cacheMiss, isTrue);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 2);
      _finish(prepare, quantum: 7);
      expect(cache.layoutBuildCount, 2);
      prepare.takeLayout().close();
      expect(external.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'a 101-child whole-column probe yields across quanta before waiting, cancel=$cancel',
      () {
        final foreignInput = _input(ranks: 3);
        final foreign = [
          for (final part in foreignInput.parts.take(3))
            cache.acquire(content: part, width: 100),
        ];
        addTearDown(() {
          for (final lease in foreign) {
            lease.release();
          }
        });
        final prepare = _open(cache, _input(), metrics: true);
        var inspected = 0;
        var sawPartial = false;
        for (var i = 0; !prepare.waitingForLayoutBudget && i < 1000; i++) {
          final step = prepare.advance(maxParts: 7);
          inspected += step.partsInspected;
          expect(step.formatUnitsPrepared, lessThanOrEqualTo(7));
          expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
          if (step.partsInspected > 0 && !step.waitingForLayoutBudget) {
            sawPartial = true;
            expect(prepare.lastBudgetRejection, isNull);
            if (cancel) break;
          }
        }
        expect(sawPartial, isTrue);
        if (cancel) {
          prepare.close();
          expect(cache.activeLeases, 3);
        } else {
          expect(inspected, 101);
          expect(prepare.waitingForLayoutBudget, isTrue);
          expect(prepare.lastBudgetRejection, isNotNull);
          final waiting = prepare.advance(maxParts: 7);
          expect(waiting.madeProgress, isFalse);
          expect(waiting.partsInspected, 0);
          for (final lease in foreign) {
            lease.release();
          }
          _finish(prepare, quantum: 7);
          expect(cache.activeLeases, 0);
          prepare.takeMetrics();
        }
        expect(
          foreign.every((lease) => cancel ? lease.isActive : !lease.isActive),
          isTrue,
        );
      },
    );
  }

  for (final metrics in [false, true]) {
    test(
      'cancelling after native children but before final numeric publication releases everything, metrics=$metrics',
      () {
        final prepare = _open(cache, _input(), metrics: metrics);
        for (var i = 0; prepare.preparedPartCount < 101 && i < 20000; i++) {
          prepare.advance(maxParts: 1);
        }
        expect(prepare.preparedPartCount, 101);
        expect(prepare.isReady, isFalse);
        expect(cache.activeLeases, greaterThan(0));
        prepare.close();
        expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
        expect(prepare.nativeLeases, isEmpty);
        expect(cache.activeLeases, 0);
        cache.close();
        expect(cache.estimatedRetainedBytes, 0);
      },
    );
  }

  test(
    'metrics finalization releases only its bounded rank prefix before readiness',
    () {
      final prepare = _open(cache, _input(), metrics: true);
      while (prepare.preparedPartCount < 101) {
        prepare.advance(maxParts: 1);
      }
      expect(cache.activeLeases, 101);
      final step = prepare.advance(maxParts: 7);
      expect(step.partsPrepared, 0);
      expect(step.formatUnitsPrepared, 7);
      expect(step.layoutsBuilt + step.picturesBuilt, 0);
      expect(step.isReady, isFalse);
      expect(cache.activeLeases, 94);
      expect(prepare.nativeLeases.length, 94);
      _finish(prepare, quantum: 7);
      expect(cache.activeLeases, 0);
      prepare.takeMetrics();
    },
  );

  test(
    'generation retirement after a partial numeric release cannot publish metrics',
    () {
      late ForumBodyRubyGroupPreparation prepare;
      var retire = false;
      prepare = _open(
        cache,
        _input(),
        metrics: true,
        ensureOwner: () {
          if (retire && cache.activeLeases < 101) prepare.close();
        },
      );
      while (prepare.preparedPartCount < 101) {
        prepare.advance(maxParts: 1);
      }
      retire = true;
      expect(() => prepare.advance(maxParts: 7), throwsStateError);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.closed);
      expect(() => prepare.takeMetrics(), throwsStateError);
      expect(prepare.nativeLeases, isEmpty);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'intrinsically impossible multi-band footprint fails after bounded probe and preserves foreign pins',
    () {
      final limited = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(limited.close);
      final external = limited.acquire(
        content: _input(ranks: 3).parts.first,
        width: 100,
      );
      addTearDown(external.release);
      final prepare = _open(limited, _input(), metrics: true);
      var failed = false;
      for (var i = 0; i < 100; i++) {
        try {
          final step = prepare.advance(maxParts: 7);
          expect(step.formatUnitsPrepared, lessThanOrEqualTo(7));
          expect(step.waitingForLayoutBudget, isFalse);
        } on ForumBodyRubyGroupPreparationException catch (error) {
          expect(
            error.failure,
            ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
          );
          failed = true;
          break;
        }
      }
      expect(failed, isTrue);
      expect(prepare.state, ForumBodyRubyGroupPreparationState.failed);
      expect(prepare.nativeLeases, isEmpty);
      expect(external.isActive, isTrue);
      expect(limited.activeLeases, 1);
    },
  );
}
