import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/emphasis_allocation_fixture.dart';

class _Scaler extends TextScaler {
  const _Scaler([this.onSize]);
  final void Function(double)? onSize;
  @override
  double scale(double size) {
    onSize?.call(size);
    return size < 20 ? size * 1.4 : size * 1.1;
  }

  @override
  double get textScaleFactor => throw StateError('Sample actual sizes');
}

ForumBodyEmphasisFragmentInput _input({
  double width = 1,
  TextDirection direction = TextDirection.ltr,
  bool selected = false,
  String? body,
  bool shadows = false,
}) {
  final fixture = body == null
      ? EmphasisAllocationFixture(
          width: width,
          direction: direction,
          scaler: const _Scaler(),
          shadows: shadows,
        )
      : EmphasisAllocationFixture(
          width: width,
          direction: direction,
          scaler: const _Scaler(),
          body: body,
          shadows: shadows,
        );
  final measure = ForumBodyEmphasisParagraphPreparation(
    content: fixture.glyphs.original,
    cache: fixture.cache,
    ensureOwner: () {},
    width: width,
    textScaler: fixture.scaler,
  );
  while (!measure.isReady) {
    measure.advance(maxParts: 32);
  }
  final paragraph = measure.takeMetrics();
  fixture.cache.close();
  final pure = ForumBodyEmphasisFragmentInputPreparation(
    paragraph: paragraph,
    startLine: selected ? paragraph.groups[1].startLine : 0,
    endLine: selected
        ? paragraph.groups[paragraph.groups.length - 2].endLine
        : paragraph.lines.length,
    ensureOwner: () {},
  );
  while (!pure.isReady) {
    pure.advance(maxParts: 32);
  }
  return pure.takeInput();
}

ForumBodyParagraphCache _cache([int entries = 32]) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyEmphasisFragmentPreparation _job(
  ForumBodyEmphasisFragmentInput input,
  ForumBodyParagraphCache cache, {
  void Function()? owner,
  void Function()? visibleOwner,
  TextScaler scaler = const _Scaler(),
  double? width,
  Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
}) {
  final job = ForumBodyEmphasisFragmentPreparation(
    input: input,
    cache: cache,
    ensureOwner: owner ?? () {},
    ensureVisibleOwner: visibleOwner,
    width: width ?? input.width,
    expectedTextScaler: scaler,
    additionalOwnedLeases: prefix,
  );
  addTearDown(job.close);
  return job;
}

ForumBodyEmphasisFragmentLayout _finish(
  ForumBodyEmphasisFragmentPreparation job, {
  bool cachedOnly = false,
  int parts = 1,
}) {
  for (var n = 0; !job.isReady && n < 300000; n++) {
    final step = job.advance(maxParts: parts, cachedOnly: cachedOnly);
    expect(step.partsPrepared, lessThanOrEqualTo(parts));
    expect(
      step.nativeLayoutsBuilt + step.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(step.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
  }
  expect(job.isReady, isTrue);
  final result = job.takeLayout();
  addTearDown(result.close);
  return result;
}

class _Images {
  final pictures = <ui.Picture>[];
  Future<List<int>> pixels(
    void Function(Canvas) draw,
    double height,
    int dpr,
  ) async {
    final recorder = ui.PictureRecorder();
    draw(
      Canvas(recorder)
        ..scale(dpr.toDouble())
        ..translate(25, 25),
    );
    final picture = recorder.endRecording();
    pictures.add(picture);
    final image = await picture.toImage(220 * dpr, (height.ceil() + 50) * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList(growable: false);
    } finally {
      image.dispose();
    }
  }

  void close() {
    for (final p in pictures) {
      p.dispose();
    }
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
    'delivered view outlives its preparation guard and follows the reader owner',
    () {
      final input = _input(body: 'AAAA'), cache = _cache(6);
      var preparing = true, reading = true;
      final job = _job(
        input,
        cache,
        owner: () {
          if (!preparing) throw StateError('Preparation retired');
        },
        visibleOwner: () {
          if (!reading) throw StateError('Reader retired');
        },
      );
      final view = _finish(job);
      preparing = false;
      job.close();
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      expect(view.sourceAt(Offset.zero).displayUtf16, inInclusiveRange(0, 4));
      expect(view.selectionBoxes(0, 4), isNotEmpty);
      expect(view.glyphBoxes(0, 4), isNotEmpty);
      final recorder = ui.PictureRecorder();
      view.paint(Canvas(recorder), Offset.zero);
      recorder.endRecording().dispose();
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      reading = false;
      expect(() => view.sourceAt(Offset.zero), throwsStateError);
      expect(() => view.selectionBoxes(0, 4), throwsStateError);
      expect(() => view.glyphBoxes(0, 4), throwsStateError);
      view.close();
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'persistent owner retirement after ready rejects transfer and drains both handles',
    () {
      final input = _input(body: 'AAAA'), cache = _cache(6);
      var active = true;
      final job = _job(
        input,
        cache,
        visibleOwner: () {
          if (!active) throw StateError('Reader retired');
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 32);
      }
      expect(cache.activeLeases, 2);
      active = false;
      expect(job.takeLayout, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'persistent owner callback cannot publish after canceling the transaction',
    () {
      final input = _input(body: 'AAAA'), cache = _cache(6);
      late ForumBodyEmphasisFragmentPreparation job;
      var cancel = false;
      job = _job(
        input,
        cache,
        visibleOwner: () {
          if (cancel) job.close();
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 32);
      }
      cancel = true;
      expect(job.takeLayout, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
  for (final direction in TextDirection.values) {
    for (final width in [1.0, 140.0]) {
      for (final selected in [false, true]) {
        test(
          'current merged source, selection and pixels $direction $width $selected',
          () async {
            final input = _input(
                  width: width,
                  direction: direction,
                  selected: selected,
                ),
                cache = _cache(),
                reference = _cache(64),
                view = _finish(_job(input, cache));
            expect(view.nativeLeases, hasLength(2));
            expect(cache.activeLeases, 2);
            expect(view.projection, same(input.paragraph.content.projection));
            expect(view.projection.text, isNot(contains('X')));
            expect(
              view.lines.first.top,
              input.paragraph.lines[input.startLine].top - input.selection.top,
            );
            expect(view.lines.last.coverageEndUtf16, input.coverageEndUtf16);
            final refs = <ForumBodyEmphasisAllocatedLayout>[];
            final groups = input.groups.toList();
            for (final group in groups) {
              final job = ForumBodyEmphasisAllocatedPreparation(
                input: group.allocation.source.rowInput!,
                allocation: group.allocation,
                plannedSceneInput: group.sceneInput,
                cache: reference,
                ensureOwner: () {},
                width: width,
                expectedTextScaler: const _Scaler(),
              );
              while (!job.isReady) {
                job.advance(maxParts: 32);
              }
              final actual = job.takeLayout();
              refs.add(actual);
              addTearDown(actual.close);
              final dy = group.top - input.selection.top;
              for (final mark in group.allocation.marks) {
                final hit = view.sourceAt(
                  mark.fontBounds.center + Offset(0, dy),
                );
                final unit =
                    group.allocation.source.input.units[group
                        .allocation
                        .source
                        .marks[mark.markIndex]
                        .unitIndex];
                expect(
                  hit.displayUtf16,
                  group.startUtf16 +
                      group.allocation.source.input.content.projection
                          .sourceAtUtf16(unit.governingUtf16)
                          .displayUtf16,
                );
                expect(hit.isExact, isFalse);
              }
              final boxes = actual.selectionBoxes(
                0,
                group.endUtf16 - group.startUtf16,
              );
              final merged = view.selectionBoxes(
                group.startUtf16,
                group.endUtf16,
              );
              expect(
                merged.map((b) => b.toRect()),
                boxes.map((b) => b.toRect().shift(Offset(0, dy))),
              );
              for (final box in boxes.where((b) => !b.toRect().isEmpty)) {
                final local = actual.sourceAt(box.toRect().center),
                    whole = view.sourceAt(box.toRect().center + Offset(0, dy));
                expect(
                  whole.displayUtf16,
                  group.startUtf16 + local.displayUtf16,
                );
                expect(whole.sourceRune, local.sourceRune);
                expect(whole.isExact, local.isExact);
              }
            }
            expect(
              view
                  .glyphBoxes(0, view.projection.text.length)
                  .every(
                    (b) => b.top >= -1e-8 && b.bottom <= view.height + 1e-8,
                  ),
              isTrue,
            );
            final images = _Images();
            addTearDown(images.close);
            final shapes = cache.layoutBuildCount,
                recordings = cache.pictureBuildCount;
            for (final dpr in [1, 3]) {
              final expected = await images.pixels(
                (c) {
                  for (var n = 0; n < refs.length; n++) {
                    refs[n].paint(
                      c,
                      Offset(0, groups[n].top - input.selection.top),
                    );
                  }
                },
                view.height,
                dpr,
              );
              expect(
                await images.pixels(
                  (c) => view.paint(c, Offset.zero),
                  view.height,
                  dpr,
                ),
                expected,
              );
            }
            expect(cache.layoutBuildCount, shapes);
            expect(cache.pictureBuildCount, recordings);
            expect(
              () => view.sourceAt(const Offset(double.nan, 0)),
              throwsArgumentError,
            );
            expect(() => view.selectionBoxes(-1, 0), throwsRangeError);
            view.close();
            expect(cache.activeLeases, 0);
            expect(() => view.selectionBoxes(0, 0), throwsStateError);
          },
        );
      }
    }
  }
  test(
    'four groups use five shared fonts and one final scene, warm reuse stays native-free',
    () {
      final input = _input(body: 'AAAA'),
          cache = _cache(6),
          cold = _job(input, cache);
      for (var n = 0; !cold.cacheMiss && n < 200000; n++) {
        final step = cold.advance(maxParts: 32, cachedOnly: true);
        expect(step.nativeLayoutsBuilt + step.picturesRecorded, 0);
      }
      expect(cold.cacheMiss, isTrue);
      expect(cache.layoutBuildCount + cache.pictureBuildCount, 0);
      final a = _finish(cold, parts: 32);
      expect(cache.layoutBuildCount, 5);
      expect(
        cache.pictureBuildCount,
        4,
      ); // Three shared first paints + ONE scene.
      expect(cache.entryCount, 6);
      final calls = <double, int>{};
      final b = _finish(
        _job(
          input,
          cache,
          scaler: _Scaler((s) {
            calls[s] = (calls[s] ?? 0) + 1;
          }),
        ),
        cachedOnly: true,
        parts: 32,
      );
      expect(calls.keys.toSet(), input.paragraph.effectiveScales.keys.toSet());
      expect(calls.values.every((n) => n == 1), isTrue);
      expect(cache.layoutBuildCount, 5);
      expect(cache.pictureBuildCount, 4);
      expect(cache.activeLeases, 4);
      expect(
        a.nativeLeases.last.nativeInputIdentity,
        b.nativeLeases.last.nativeInputIdentity,
      );
      a.close();
      b.close();
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'long fragment retains two handles and no per-group first-paint recording',
    () {
      final input = _input(body: 'A' * 128),
          cache = _cache(6),
          view = _finish(_job(input, cache), parts: 64);
      expect(input.groups, hasLength(128));
      expect(cache.layoutBuildCount, 5);
      expect(cache.pictureBuildCount, 4);
      expect(cache.activeLeases, 2);
      expect(view.lines, hasLength(128));
    },
  );
  test(
    'paint proof omits native SPACE suffixes but keeps selection and terminal source',
    () {
      final input = _input(body: 'A   A\n', width: 60),
          cache = _cache(),
          view = _finish(_job(input, cache));
      var suffixes = 0;
      for (final line in input.paragraph.lines) {
        final start = line.unpaintedTrailingSpaceStartUtf16,
            end = line.endUtf16;
        if (start < end) {
          suffixes++;
          expect(view.selectionBoxes(start, end), isNotEmpty);
          expect(view.glyphBoxes(start, end), isEmpty);
        }
      }
      expect(suffixes, greaterThan(0));
      expect(input.paragraph.hasTerminalEmptyLine, isTrue);
      expect(view.lines.last.coverageStartUtf16, view.projection.text.length);
      expect(
        view.sourceAt(Offset(0, view.height + 1000)).displayUtf16,
        view.projection.text.length,
      );
    },
  );
  test(
    'width, scaling, own budget and declared prefix reject without native work',
    () {
      final input = _input(body: 'AAAA'), cache = _cache(5);
      expect(
        () => _job(input, cache, width: 2),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      final scaled = _job(input, cache, scaler: TextScaler.noScaling);
      expect(
        () => scaled.advance(maxParts: 32),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      final limited = _job(input, cache);
      expect(
        () => _finish(limited),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount + cache.pictureBuildCount, 0);
      final prefixCache = _cache(6);
      final pin = prefixCache.acquire(
        content: input.paragraph.glyphInput.glyphs,
        width: 1,
        textScaler: input.paragraph.textScaler,
      );
      final before = prefixCache.layoutBuildCount;
      final prefixed = _job(input, prefixCache, prefix: () => [pin]);
      expect(
        () => _finish(prefixed),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(prefixCache.activeLeases, 1);
      expect(prefixCache.layoutBuildCount, before);
      pin.release();
    },
  );
  test('external pins wait in the same transaction then resume', () {
    final input = _input(body: 'AAAA'), cache = _cache(6);
    final pins = [
      for (final width in [2.0, 3.0])
        cache.acquire(
          content: input.paragraph.glyphInput.glyphs,
          width: width,
          textScaler: input.paragraph.textScaler,
        ),
    ];
    final job = _job(input, cache);
    var waiting = false;
    for (var n = 0; !waiting && n < 200000; n++) {
      waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
    }
    expect(waiting, isTrue);
    final builds = cache.layoutBuildCount, handles = cache.activeLeases;
    for (var n = 0; n < 3; n++) {
      expect(job.advance(maxParts: 32).waitingForLayoutBudget, isTrue);
      expect(cache.activeLeases, handles);
      expect(cache.layoutBuildCount, builds);
    }
    for (final pin in pins) {
      pin.release();
    }
    _finish(job);
    expect(cache.activeLeases, 2);
  });
  for (final cacheRetires in [false, true]) {
    for (final at in [1, 2, 3, 4]) {
      test(
        'retirement while recording $at cache=$cacheRetires never publishes',
        () {
          final input = _input(body: 'AAAA');
          var active = true, pictures = 0, disposed = 0;
          late ForumBodyParagraphCache cache;
          cache = ForumBodyParagraphCache(
            maxEntries: 6,
            maxEstimatedBytes: 1 << 26,
          );
          final oldCreate = ui.Picture.onCreate,
              oldDispose = ui.Picture.onDispose;
          ui.Picture.onCreate = (_) {
            if (++pictures == at) {
              if (cacheRetires) {
                cache.close();
              } else {
                active = false;
              }
            }
          };
          ui.Picture.onDispose = (_) {
            disposed++;
          };
          addTearDown(cache.close);
          final job = _job(
            input,
            cache,
            owner: () {
              if (!active) throw StateError('Retired');
            },
          );
          try {
            expect(() => _finish(job), throwsStateError);
            cache.close();
          } finally {
            ui.Picture.onCreate = oldCreate;
            ui.Picture.onDispose = oldDispose;
          }
          expect(pictures, at);
          expect(disposed, at);
          expect(cache.activeLeases, 0);
          expect(job.isReady, isFalse);
        },
      );
    }
  }
  test(
    'ready/visible owner retirement and explicit cancellation release all',
    () {
      final input = _input(body: 'AAAA'), cache = _cache(6);
      var active = true;
      void guard() {
        if (!active) throw StateError('Retired');
      }

      final ready = _job(input, cache, owner: guard);
      while (!ready.isReady) {
        ready.advance(maxParts: 32);
      }
      active = false;
      expect(ready.takeLayout, throwsStateError);
      expect(cache.activeLeases, 0);
      active = true;
      final view = _finish(_job(input, cache, owner: guard));
      active = false;
      expect(() => view.sourceAt(Offset.zero), throwsStateError);
      expect(() => view.glyphBoxes(0, 1), throwsStateError);
      view.close();
      active = true;
      final cancelled = _job(input, cache);
      for (var n = 0; n < 200; n++) {
        cancelled.advance(maxParts: 1);
      }
      cancelled.close();
      expect(cancelled.takeLayout, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
}
