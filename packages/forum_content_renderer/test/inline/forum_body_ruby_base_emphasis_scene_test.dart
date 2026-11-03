import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_emphasis_fixture.dart';

ForumBodyParagraphCache _cache({int entries = 32, int bytes = 1 << 24}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyRubyBaseEmphasisPlan _plan(
  ForumBodyParagraphCache cache, {
  RubyEmphasisFixture? fixture,
  TextScaler scaler = TextScaler.noScaling,
  bool band = false,
  bool empty = false,
}) {
  final source = fixture ?? rubyEmphasisFixture();
  final line = measureRubyEmphasisLine(
    cache,
    content: source,
    scaler: scaler,
    request: band
        ? (input) => ForumBodyTextRequest.bandChild(
            band: ForumBodyTextBandContent(
              contexts: [input.glyphInput.glyphs, source.annotations.first],
            ),
            childIndex: 0,
          )
        : null,
  );
  final group = measureRubyEmphasisGroup(
    cache,
    line,
    fixture: source,
    sides: const [
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
      ForumBodyRubySide.over,
    ],
  );
  final geometryJob = ForumBodyRubyBaseEmphasisPreparation(
    line: line,
    group: empty
        ? measureRubyEmphasisGroup(
            cache,
            line,
            fixture: source,
            sides: const [
              ForumBodyRubySide.over,
              ForumBodyRubySide.under,
              ForumBodyRubySide.over,
            ],
            empty: true,
          ).alignedTo(ForumBodyRubyLevelMetrics.single(group))
        : group,
    ensureOwner: () {},
  );
  while (!geometryJob.isReady) {
    geometryJob.advance(maxParts: 1);
  }
  final job = ForumBodyRubyBaseEmphasisPlanPreparation(
    geometry: geometryJob.takeGeometry(),
    ensureOwner: () {},
  );
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), lessThanOrEqualTo(1));
  }
  expect(cache.pictureBuildCount, 0);
  expect(cache.activeLeases, 0);
  return job.takePlan();
}

ForumBodyRubyBaseEmphasisScenePreparation _work(
  ForumBodyParagraphCache cache,
  ForumBodyRubyBaseEmphasisPlan plan, {
  void Function()? owner,
  void Function()? visibleOwner,
  TextScaler? scaler,
  Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
}) {
  final work = ForumBodyRubyBaseEmphasisScenePreparation(
    input: plan.geometry.line.input,
    plan: plan,
    width: plan.geometry.line.requestWidth,
    cache: cache,
    ensureOwner: owner ?? () {},
    ensureVisibleOwner: visibleOwner,
    expectedTextScaler: scaler ?? plan.geometry.line.textScaler,
    additionalOwnedLeases: prefix,
  );
  addTearDown(work.close);
  return work;
}

ForumBodyRubyBaseEmphasisLayout _finish(
  ForumBodyRubyBaseEmphasisScenePreparation work, {
  bool cachedOnly = false,
}) {
  for (var i = 0; !work.isReady; i++) {
    expect(i, lessThan(10000));
    final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(
      step.nativeLayoutsBuilt + step.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(step.waitingForLayoutBudget, isFalse);
    expect(work.cacheMiss, isFalse);
  }
  final layout = work.takeLayout();
  addTearDown(layout.close);
  return layout;
}

Future<List<int>> _pixels(
  ForumBodyRubyBaseEmphasisLayout view,
  int dpr,
  void Function(Canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(
    Canvas(recorder)
      ..scale(dpr.toDouble())
      ..translate(30, 80),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (view.bounds.width.ceil() + 100) * dpr,
      (view.bounds.height.ceil() + 200) * dpr,
    );
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
  for (final direction in TextDirection.values) {
    for (final nonlinear in [false, true]) {
      for (final empty in [false, true]) {
        test('actual source and scene match native painter $direction '
            'nonlinear=$nonlinear empty=$empty', () async {
          final cache = _cache(),
              fixture = rubyEmphasisFixture(
                direction: direction,
                paintEffects: true,
              );
          final scaler = nonlinear
              ? const RubyEmphasisNonlinearScaler()
              : TextScaler.noScaling;
          final plan = _plan(
            cache,
            fixture: fixture,
            scaler: scaler,
            empty: empty,
          );
          cache.clearUnpinned();
          final view = _finish(_work(cache, plan, scaler: scaler));
          expect(view.projection, same(fixture.base.projection));
          expect(view.isOwnedBy(cache), isTrue);
          expect(view.nativeLeases, hasLength(2));
          expect(cache.activeLeases, 2);
          cache.clearUnpinned();
          expect(cache.entryCount, 2);
          final base = TextPainter(
            text: plan.geometry.line.input.glyphInput.glyphs.textSpan,
            textDirection: direction,
            textScaler: scaler,
          )..layout();
          final markers = [
            for (final placed in plan.geometry.marks)
              TextPainter(
                text: TextSpan(
                  text: placed.mark.input.mark,
                  style: placed.mark.input.textStyle,
                ),
                textDirection: placed.mark.input.textDirection,
                textScaler: scaler,
              )..layout(),
          ];
          try {
            final shapes = cache.layoutBuildCount,
                pictures = cache.pictureBuildCount;
            for (final dpr in [1, 3]) {
              final actual = await _pixels(
                view,
                dpr,
                (canvas) => view.paint(canvas, Offset.zero),
              );
              final expected = await _pixels(view, dpr, (canvas) {
                base.paint(canvas, plan.geometry.group.baseOffset);
                for (var i = 0; i < markers.length; i++) {
                  final mark = plan.geometry.marks[i];
                  canvas.save();
                  canvas.translate(
                    mark.baselineOrigin.dx,
                    mark.baselineOrigin.dy,
                  );
                  markers[i].paint(canvas, mark.fontOffset);
                  canvas.restore();
                }
              });
              expect(actual, expected, reason: 'DPR$dpr');
            }
            expect(cache.layoutBuildCount, shapes);
            expect(cache.pictureBuildCount, pictures);
            final boxes = view.selectionBoxes(0, view.projection.text.length);
            final direct = base.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: view.projection.text.length,
              ),
            );
            expect(boxes.length, direct.length);
            for (var i = 0; i < boxes.length; i++) {
              expect(
                boxes[i].toRect(),
                direct[i].toRect().shift(plan.geometry.group.baseOffset),
              );
            }
            for (final mark in plan.geometry.marks) {
              final hit = view.sourceAt(mark.fontBounds.center);
              final unit = view.input.units[mark.mark.unitIndex];
              final expected = view.projection.sourceAtUtf16(
                unit.governingUtf16,
              );
              expect(hit.sourceRune, expected.sourceRune);
              expect(hit.displayUtf16, expected.displayUtf16);
              expect(hit.isExact, isFalse);
            }
            expect(view.projection.text.contains('注音'), isFalse);
          } finally {
            base.dispose();
            for (final marker in markers) {
              marker.dispose();
            }
          }
        });
      }
    }
  }
  test('shared band source keeps its real child selector', () {
    final cache = _cache(), plan = _plan(cache, band: true);
    final base = plan.pictureInput.commands.first;
    expect(base.bandChildIndex, 0);
    final view = _finish(_work(cache, plan));
    expect(view.nativeLeases.first, isA<ForumBodyTextBandChildLease>());
    expect(view.selectionBoxes(0, view.projection.text.length), isNotEmpty);
    expect(cache.activeLeases, 2);
  });
  test('warm scene replays with fresh ownership and no native work', () {
    final cache = _cache(), plan = _plan(cache);
    final first = _finish(_work(cache, plan));
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final second = _finish(_work(cache, plan), cachedOnly: true);
    expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
    expect(
      first.nativeLeases.last.nativeInputIdentity,
      second.nativeLeases.last.nativeInputIdentity,
    );
    first.close();
    second.ensureActive();
    expect(cache.activeLeases, 2);
  });
  test('cached-only cold binding does not shape or install a scene', () {
    final cache = _cache(), plan = _plan(cache);
    cache.clearUnpinned();
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final work = _work(cache, plan);
    for (var i = 0; !work.cacheMiss; i++) {
      expect(i, lessThan(10000));
      work.advance(maxParts: 1, cachedOnly: true);
    }
    expect(work.isReady, isFalse);
    expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
    work.close();
    expect(cache.activeLeases, 0);
  });
  test('source identity and half-font scales cannot borrow a pure scene', () {
    final cache = _cache(), plan = _plan(cache);
    final source = ForumBodyEmphasisTextPreparation(
      content: plan.geometry.line.input.content,
    );
    while (!source.isReady) {
      source.advance(maxParts: 1);
    }
    expect(
      () => ForumBodyRubyBaseEmphasisScenePreparation(
        input: source.takeInput(),
        plan: plan,
        cache: cache,
        ensureOwner: () {},
        width: plan.geometry.line.requestWidth,
        expectedTextScaler: TextScaler.noScaling,
      ),
      throwsA(isA<ForumBodyEmphasisLineException>()),
    );
    final work = _work(
      cache,
      plan,
      scaler: const RubyEmphasisNonlinearScaler(),
    );
    expect(() => _finish(work), throwsA(isA<ForumBodyEmphasisLineException>()));
    expect(cache.activeLeases, 0);
  });
  test(
    'scene footprint rejects intrinsic over-budget input before acquisition',
    () {
      final plan = _plan(_cache(), fixture: rubyEmphasisFixture(text: 'AB'));
      final cache = _cache(entries: 2), work = _work(cache, plan);
      expect(
        () => _finish(work),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'outside pin waits along the same scene work and resumes on release',
    () {
      final plan = _plan(_cache(), fixture: rubyEmphasisFixture(text: 'AB'));
      final cache = _cache(entries: 3);
      final outside = cache.acquire(
        content: rubyEmphasisFixture(text: 'outside', emphasis: 'none').base,
        width: 100,
      );
      addTearDown(outside.release);
      final work = _work(cache, plan);
      for (var i = 0; ; i++) {
        expect(i, lessThan(10000));
        if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
      }
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      expect(work.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      outside.release();
      _finish(work).ensureActive();
      expect(cache.activeLeases, 2);
    },
  );
  test('delivered source and scene keep the persistent reader guard', () {
    final cache = _cache(), plan = _plan(cache);
    var preparing = true, reading = true;
    final work = _work(
      cache,
      plan,
      owner: () {
        if (!preparing) throw StateError('Preparation retired');
      },
      visibleOwner: () {
        if (!reading) throw StateError('Reader retired');
      },
    );
    final view = _finish(work);
    preparing = false;
    work.close();
    view.ensureActive();
    view.sourceAt(Offset.zero);
    reading = false;
    expect(view.ensureActive, throwsStateError);
    expect(() => view.sourceAt(Offset.zero), throwsStateError);
    expect(() => view.selectionBoxes(0, 1), throwsStateError);
    view.close();
    expect(cache.activeLeases, 0);
  });
  test(
    'retirement at every boundary releases fonts, aliases and final scene',
    () {
      final plan = _plan(_cache(), fixture: rubyEmphasisFixture(text: 'AB'));
      final warmupCache = _cache(), warmup = _work(warmupCache, plan);
      var count = 0;
      while (!warmup.isReady) {
        warmup.advance(maxParts: 1);
        count++;
      }
      warmup.close();
      for (var boundary = 0; boundary <= count; boundary++) {
        final cache = _cache();
        var alive = true;
        final work = _work(
          cache,
          plan,
          owner: () {
            if (!alive) throw StateError('Reader retired');
          },
        );
        for (var i = 0; i < boundary; i++) {
          work.advance(maxParts: 1);
        }
        alive = false;
        expect(
          work.isReady ? work.takeLayout : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 0);
        cache.close();
      }
    },
  );
  test(
    'owned prefix and final scene are rejected together before new shaping',
    () {
      final plan = _plan(_cache(), fixture: rubyEmphasisFixture(text: 'AB'));
      final cache = _cache(entries: 3);
      final prefix = cache.acquire(
        content: rubyEmphasisFixture(text: 'prefix', emphasis: 'none').base,
        width: 100,
      );
      addTearDown(prefix.release);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final work = _work(cache, plan, prefix: () => [prefix]);
      expect(
        () => _finish(work),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      expect(prefix.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );
  test('prefix EOF retirement releases only the transaction resources', () {
    final cache = _cache(), plan = _plan(cache);
    final prefix = cache.acquire(
      content: rubyEmphasisFixture(text: 'prefix', emphasis: 'none').base,
      width: 100,
    );
    addTearDown(prefix.release);
    var alive = true;
    Iterable<ForumBodyNativeParagraphLease> owned() sync* {
      yield prefix;
      alive = false;
    }

    final work = _work(
      cache,
      plan,
      prefix: owned,
      owner: () {
        if (!alive) throw StateError('Reader retired');
      },
    );
    expect(() => _finish(work), throwsStateError);
    expect(prefix.isActive, isTrue);
    expect(cache.activeLeases, 1);
  });
  for (final record in [1, 2]) {
    test(
      'retirement during native recording $record cannot deliver a scene',
      () {
        final cache = _cache(),
            plan = _plan(
              cache,
              fixture: rubyEmphasisFixture(text: 'AB'),
              band: record == 2,
            );
        cache.clearUnpinned();
        var alive = true, created = 0;
        final work = _work(
          cache,
          plan,
          owner: () {
            if (!alive) throw StateError('Reader retired');
          },
        );
        final previous = ui.Picture.onCreate;
        ui.Picture.onCreate = (_) {
          if (++created == record) alive = false;
        };
        try {
          expect(() => _finish(work), throwsStateError);
        } finally {
          ui.Picture.onCreate = previous;
          work.close();
        }
        expect(created, record);
        expect(cache.activeLeases, 0);
      },
    );
  }
  test(
    'owner callbacks cannot reenter the preparation or take its resources',
    () {
      final cache = _cache(), plan = _plan(cache);
      ForumBodyRubyBaseEmphasisScenePreparation? work;
      work = _work(
        cache,
        plan,
        owner: () {
          if (work == null) return;
          expect(work.advance, throwsStateError);
          expect(work.takeLayout, throwsStateError);
        },
      );
      _finish(work).ensureActive();
      expect(cache.activeLeases, 2);
    },
  );
}
