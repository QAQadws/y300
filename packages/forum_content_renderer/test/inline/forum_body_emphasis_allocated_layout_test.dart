import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_native_space_span.dart';

import 'test_support/emphasis_allocation_fixture.dart';

class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final void Function(double) callback;
  @override
  double scale(double size) {
    callback(size);
    return size;
  }

  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

class _LargeMarks extends TextScaler {
  const _LargeMarks();
  @override
  double scale(double size) => size < 20 ? 500 : size;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyEmphasisRowAllocation _allocate(
  EmphasisAllocationFixture c,
  EmphasisAllocationRowFixture r,
) {
  final j = c.prepare(r);
  while (!j.isReady) {
    j.advance(maxParts: 1);
  }
  return j.takeAllocation();
}

ForumBodyEmphasisAllocatedPreparation _job(
  EmphasisAllocationFixture c,
  ForumBodyEmphasisRowAllocation a, {
  ForumBodyParagraphCache? cache,
  void Function()? owner,
  TextScaler? scaler,
  double? width,
  Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
}) => ForumBodyEmphasisAllocatedPreparation(
  input: a.source.rowInput!,
  allocation: a,
  cache: cache ?? c.cache,
  ensureOwner: owner ?? () {},
  width: width ?? c.width,
  expectedTextScaler: scaler ?? c.scaler,
  additionalOwnedLeases: prefix,
);
ForumBodyEmphasisAllocatedLayout _finish(
  ForumBodyEmphasisAllocatedPreparation j, {
  bool cachedOnly = false,
}) {
  addTearDown(j.close);
  for (var n = 0; !j.isReady && n < 50000; n++) {
    final s = j.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(s.partsPrepared, lessThanOrEqualTo(1));
    expect(s.nativeLayoutsBuilt + s.picturesRecorded, lessThanOrEqualTo(1));
    expect(s.waitingForLayoutBudget, isFalse);
    expect(j.cacheMiss, isFalse);
  }
  expect(j.isReady, isTrue);
  return j.takeLayout();
}

class _Images {
  final pictures = <ui.Picture>[];
  Future<List<int>> pixels(
    void Function(Canvas) draw,
    double height,
    int dpr,
  ) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..scale(dpr.toDouble())
      ..translate(25, 25);
    draw(c);
    final p = rec.endRecording();
    pictures.add(p);
    final image = await p.toImage(220 * dpr, (height.ceil() + 50) * dpr);
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
    pictures.clear();
  }
}

void _exact(List<int> a, List<int> b, String label) {
  expect(a.length, b.length);
  var count = 0, max = 0;
  for (var k = 0; k < a.length; k++) {
    final d = (a[k] - b[k]).abs();
    if (d > 0) {
      count++;
    }
    if (d > max) {
      max = d;
    }
  }
  expect(count, 0, reason: '$label max=$max');
}

// Independent whole-context Flutter painters: no prepared scene commands or
// current phase selectors are used to construct the reference drawing.
class _Oracle {
  _Oracle(this.plan, ForumBodyParagraphLayout source) {
    final content = plan.paintInput;
    for (final layer in [
      content.background,
      content.foreground,
      content.decoration,
    ]) {
      final body = layer.textSpan, indent = source.firstLineIndent;
      phases.add(
        TextPainter(
          text: indent.requestedAdvance > 0
              ? TextSpan(
                  style: body.style,
                  children: [
                    ForumBodyNativeSpaceSpan.nonBreaking(indent.appliedAdvance),
                    ...body.children!,
                  ],
                )
              : body,
          textDirection: layer.style.textDirection,
          textAlign: layer.style.textAlign,
          textScaler: plan.source.textScaler,
          locale: layer.style.textStyle.locale,
          strutStyle: StrutStyle.fromTextStyle(
            layer.style.textStyle,
            height:
                plan.reference.rowIsolationPitch /
                plan.source.textScaler.scale(layer.style.textStyle.fontSize!),
            leading: 0,
            forceStrutHeight: true,
          ),
        )..layout(
          minWidth: source.width - 2 * source.horizontalInset,
          maxWidth: source.width - 2 * source.horizontalInset,
        ),
      );
    }
    inset = source.horizontalInset;
    for (final mark in plan.source.marks) {
      final input = mark.input;
      markers.add(
        TextPainter(
          text: TextSpan(text: input.mark, style: input.textStyle),
          textDirection: input.textDirection,
          textScaler: plan.source.textScaler,
          locale: input.textStyle.locale,
        )..layout(),
      );
    }
  }
  final ForumBodyEmphasisRowAllocation plan;
  final phases = <TextPainter>[], markers = <TextPainter>[];
  late final double inset;
  void paint(Canvas canvas) {
    for (var index = 0; index < plan.rows.length; index++) {
      final row = plan.rows[index], line = row.physicalLine;
      final native = plan.reference.isolatedLines[line.lineIndex];
      if (native.coverageStartUtf16 != native.coverageEndUtf16) {
        for (var layer = 0; layer < 3; layer++) {
          final offset = layer == 1 ? row.glyphOffset : row.logicalOffset;
          canvas.save();
          try {
            canvas.translate(offset.dx, offset.dy);
            canvas.clipRect(
              Rect.fromLTRB(
                -16384,
                line.selector.clipTop,
                plan.width + 16384,
                line.selector.clipBottom,
              ),
              doAntiAlias: false,
            );
            phases[layer].paint(canvas, Offset(inset, 0));
          } finally {
            canvas.restore();
          }
        }
      }
      for (final placed in plan.marks) {
        final original = plan.source.marks[placed.markIndex];
        if (original.lineIndex != index) {
          continue;
        }
        canvas.save();
        try {
          canvas.translate(placed.offset.dx, placed.offset.dy);
          canvas.scale(original.fitScale);
          markers[placed.markIndex].paint(canvas, Offset.zero);
        } finally {
          canvas.restore();
        }
      }
    }
  }

  void close() {
    for (final painter in [...phases, ...markers]) {
      painter.dispose();
    }
  }
}

void _verifySources(
  ForumBodyEmphasisAllocatedLayout visible,
  ForumBodyEmphasisRowAllocation plan,
  ForumBodyParagraphRowView oracle,
) {
  expect(visible.projection, same(plan.source.input.content.projection));
  final original = oracle.selectionBoxes(0, visible.projection.text.length);
  final actual = visible.selectionBoxes(0, visible.projection.text.length);
  expect(actual.length, original.length);
  for (var n = 0; n < original.length; n++) {
    final native = original[n].toRect().shift(
      Offset(0, oracle.selector.originY),
    );
    final row = plan.rows.singleWhere(
      (r) =>
          native.top >= r.physicalLine.selector.clipTop &&
          native.bottom <= r.physicalLine.selector.clipBottom,
    );
    final placed = native.shift(row.logicalOffset);
    expect(actual[n].toRect(), placed);
    expect(actual[n].direction, original[n].direction);
    if (plan.marks.any((m) => m.fontBounds.contains(placed.center))) continue;
    final expected = oracle.sourceAt(original[n].toRect().center),
        hit = visible.sourceAt(placed.center);
    expect(hit.sourceRune, expected.sourceRune);
    expect(hit.displayUtf16, expected.displayUtf16);
  }
  for (final mark in plan.marks) {
    final unit =
        plan.source.input.units[plan.source.marks[mark.markIndex].unitIndex];
    final expected = visible.projection.sourceAtUtf16(unit.governingUtf16),
        hit = visible.sourceAt(mark.fontBounds.center);
    expect(hit.sourceRune, expected.sourceRune);
    expect(hit.isExact, isFalse);
  }
  expect(
    () => visible.sourceAt(const Offset(double.nan, 0)),
    throwsArgumentError,
  );
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
      // Negative tracking reserves one logical pixel at each horizontal edge.
      for (final width in [3.0, 140.0]) {
        for (final height in ['.4', '1.6', '37px']) {
          test('allocated pixels $direction nonlinear=$nonlinear '
              'width=$width height=$height', () async {
            final c = EmphasisAllocationFixture(
              width: width,
              height: height,
              direction: direction,
              scaler: nonlinear ? const _Nonlinear() : TextScaler.noScaling,
              indent: true,
              shadows: true,
              tracking: -1,
              body:
                  '<span style="background-color:#80667788;'
                  'text-decoration:underline">AB 👩‍👩‍👧‍👦 </span>'
                  'e<b style="font-size:31px">́</b> '
                  '<span style="text-emphasis-position:under;'
                  'background-color:#80ccaa22">؀A 中</span> '
                  '<span style="visibility:hidden">H</span>\n\n',
            );
            for (var start = 0; start < c.isolated.layout.lineCount;) {
              final r = c.row(start),
                  plan = _allocate(c, r),
                  oracle = _Oracle(plan, c.isolated.layout),
                  images = _Images();
              final visible = _finish(_job(c, plan));
              try {
                _verifySources(visible, plan, r.view);
                for (final dpr in [1, 3]) {
                  final expected = await images.pixels(
                    oracle.paint,
                    plan.height,
                    dpr,
                  );
                  final actual = await images.pixels(
                    (canvas) => visible.paint(canvas, Offset.zero),
                    plan.height,
                    dpr,
                  );
                  _exact(expected, actual, 'group=$start DPR$dpr');
                }
              } finally {
                visible.close();
                images.close();
                oracle.close();
              }
              start = r.view.selector.endLine;
            }
          });
        }
      }
    }
  }
  test(
    'allocated scenes draw, map current sources and retire phase aliases',
    () async {
      final c = EmphasisAllocationFixture(width: 1, shadows: true);
      var spanning = 0;
      for (var start = 0; start < c.isolated.layout.lineCount;) {
        final r = c.row(start), a = _allocate(c, r), images = _Images();
        final before = c.cache.activeLeases;
        final visible = _finish(_job(c, a));
        expect(c.cache.activeLeases, before + 2);
        expect(visible.height, a.height);
        expect(visible.isPaintPrepared, isTrue);
        expect(visible.nativeLeases.length, 2);
        _verifySources(visible, a, r.view);
        for (final dpr in [1, 3]) {
          final first = await images.pixels(
            (c) => visible.paint(c, Offset.zero),
            visible.height,
            dpr,
          );
          final builds = c.cache.layoutBuildCount,
              recordings = c.cache.pictureBuildCount;
          final second = await images.pixels(
            (c) => visible.paint(c, Offset.zero),
            visible.height,
            dpr,
          );
          _exact(first, second, 'cached scene replay DPR$dpr');
          expect(c.cache.layoutBuildCount, builds);
          expect(c.cache.pictureBuildCount, recordings);
        }
        if (a.rows.length > 1) spanning++;
        visible.close();
        images.close();
        expect(c.cache.activeLeases, before);
        start = r.view.selector.endLine;
      }
      expect(spanning, greaterThan(0));
    },
  );
  test(
    'cached-only miss resumes the same transaction and warm scene hits do no native work',
    () {
      final c = EmphasisAllocationFixture(), r = c.row(0), a = _allocate(c, r);
      c.cache.close();
      final cache = ForumBodyParagraphCache(
        maxEntries: 32,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final j = _job(c, a, cache: cache);
      for (var n = 0; !j.cacheMiss && n < 10000; n++) {
        j.advance(maxParts: 1, cachedOnly: true);
      }
      expect(j.cacheMiss, isTrue);
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      final first = _finish(j);
      final input = first.pictureInput;
      first.close();
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final second = _finish(_job(c, a, cache: cache), cachedOnly: true);
      expect(second.pictureInput, input);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      second.close();
      expect(cache.activeLeases, 0);
    },
  );
  test('whole parents are charged before any native acquisition', () {
    final c = EmphasisAllocationFixture(width: 1);
    final a = _allocate(c, c.row(0));
    final parents = a.nativeFootprint
        .where((slot) => slot.request is ForumBodyParagraphTextRequest)
        .toList();
    expect(parents, hasLength(4));
    for (final parent in parents) {
      expect(parent.minimumLineCount, c.reference.lineCount);
      expect(parent.minimumLineCount, greaterThan(a.rows.length));
      expect(
        (parent.request as ForumBodyParagraphTextRequest).content.projection,
        same(c.glyphs.glyphs.projection),
      );
    }
    final cache = ForumBodyParagraphCache(
      maxEntries: 3,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    expect(
      () => _finish(_job(c, a, cache: cache)),
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
  });

  for (final declaredPrefix in [false, true]) {
    test(
      'caller pins declared=$declaredPrefix distinguish failure from wait',
      () {
        final c = EmphasisAllocationFixture(body: 'AB CD EF');
        final a = _allocate(c, c.row(0));
        c.cache.close();
        final cache = ForumBodyParagraphCache(
          maxEntries: 6,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final pins = [
          for (var index = 0; index < 2; index++)
            cache.acquire(
              content: ForumBodyParagraphContent.anonymousInline(
                identity: c.glyphs.glyphs.identity,
                fontRevision: 'caller-prefix-$index',
                styleRevision: c.glyphs.glyphs.styleRevision,
                style: c.glyphs.glyphs.style,
              ),
              width: 100,
            ),
        ];
        final j = _job(
          c,
          a,
          cache: cache,
          prefix: declaredPrefix ? () => pins : null,
        );
        if (declaredPrefix) {
          final builds = cache.layoutBuildCount;
          expect(
            () => _finish(j),
            throwsA(
              isA<ForumBodyParagraphBudgetException>().having(
                (e) => e.failure,
                'failure',
                ForumBodyParagraphBudgetFailure.content,
              ),
            ),
          );
          expect(cache.layoutBuildCount, builds);
          expect(cache.activeLeases, 2);
          for (final pin in pins) {
            expect(pin.isActive, isTrue);
            pin.release();
          }
        } else {
          var waiting = false;
          for (var n = 0; !waiting && n < 50000; n++) {
            waiting = j.advance(maxParts: 1).waitingForLayoutBudget;
          }
          expect(waiting, isTrue);
          final builds = cache.layoutBuildCount;
          for (var n = 0; n < 3; n++) {
            expect(j.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
          }
          expect(cache.layoutBuildCount, builds);
          for (final pin in pins) {
            pin.release();
          }
          _finish(j).close();
        }
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'scene remains drawable through phase eviction and exact rebind',
    () async {
      final c = EmphasisAllocationFixture(), a = _allocate(c, c.row(0));
      c.cache.close();
      final cache = ForumBodyParagraphCache(
        maxEntries: 32,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final first = _finish(_job(c, a, cache: cache)), images = _Images();
      addTearDown(first.close);
      addTearDown(images.close);
      cache.clearUnpinned();
      expect(cache.entryCount, 2);
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final expected = await images.pixels(
        (canvas) => first.paint(canvas, Offset.zero),
        a.height,
        3,
      );
      final j = _job(c, a, cache: cache);
      for (var n = 0; !j.cacheMiss && n < 50000; n++) {
        j.advance(maxParts: 1, cachedOnly: true);
      }
      expect(j.cacheMiss, isTrue);
      expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
      final second = _finish(j);
      try {
        expect(cache.layoutBuildCount, before.$1 + 4);
        expect(cache.pictureBuildCount, before.$2 + 3);
        expect(second.pictureInput, first.pictureInput);
        _exact(
          expected,
          await images.pixels(
            (canvas) => second.paint(canvas, Offset.zero),
            a.height,
            3,
          ),
          'phase eviction',
        );
        expect(
          second.sourceAt(a.fontBounds.center).sourceRune,
          first.sourceAt(a.fontBounds.center).sourceRune,
        );
      } finally {
        second.close();
        first.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'changed source input, width and actual scaling reject before shaping',
    () {
      final c = EmphasisAllocationFixture(), r = c.row(0), a = _allocate(c, r);
      final baseline = c.cache.activeLeases, builds = c.cache.layoutBuildCount;
      expect(
        () => _job(c, a, width: c.width + 1),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => ForumBodyEmphasisAllocatedPreparation(
          input: c.row(0).metrics.rowInput!,
          allocation: a,
          cache: c.cache,
          ensureOwner: () {},
          width: c.width,
          expectedTextScaler: c.scaler,
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => _finish(_job(c, a, scaler: const _Nonlinear())),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(c.cache.layoutBuildCount, builds);
      expect(c.cache.activeLeases, baseline);
    },
  );

  test('caller scaler is sampled once per size and retirement is guarded', () {
    final c = EmphasisAllocationFixture(), a = _allocate(c, c.row(0));
    final calls = <double, int>{};
    final visible = _finish(
      _job(
        c,
        a,
        scaler: _CallbackScaler((size) {
          calls.update(size, (n) => n + 1, ifAbsent: () => 1);
        }),
      ),
    );
    visible.close();
    expect(calls.keys.toSet(), a.source.effectiveScales.keys.toSet());
    expect(calls.values, everyElement(1));
    final baseline = c.cache.activeLeases;
    late ForumBodyEmphasisAllocatedPreparation j;
    j = _job(c, a, scaler: _CallbackScaler((_) => j.close()));
    expect(() => j.advance(maxParts: 1), throwsStateError);
    expect(c.cache.activeLeases, baseline);
  });

  test(
    'large marker padding keeps source hits inside its allocated physical row',
    () {
      final c = EmphasisAllocationFixture(
        width: 1,
        scaler: const _LargeMarks(),
        body: '؀<span style="font-size:31px">A</span>',
      );
      final r = c.row(0), a = _allocate(c, r);
      expect(a.rows.length, greaterThan(1));
      expect(a.height, greaterThan(r.metrics.height));
      final visible = _finish(_job(c, a));
      addTearDown(visible.close);
      for (final row in a.rows) {
        final expected = r.view.sourceAt(
          Offset(
            1000,
            row.physicalLine.fontBounds.center.dy - r.view.selector.originY,
          ),
        );
        // Outside the narrow marker, but within any extra row allocation. A hit
        // must never use the neighbouring isolated line just because Y is large.
        for (final y in [row.flowTop, row.flowBottom - .01]) {
          final point = Offset(1000, y);
          expect(visible.sourceAt(point).displayUtf16, expected.displayUtf16);
        }
      }
    },
  );

  for (final retireCache in [false, true]) {
    for (final retireAt in [1, 2, 3, 4]) {
      test(
        'retirement during recording $retireAt prevents publication cache=$retireCache',
        () {
          final c = EmphasisAllocationFixture(), a = _allocate(c, c.row(0));
          c.cache.close();
          final cache = ForumBodyParagraphCache(
            maxEntries: 32,
            maxEstimatedBytes: 1 << 24,
          );
          addTearDown(cache.close);
          final j = _job(c, a, cache: cache);
          final oldCreate = ui.Picture.onCreate,
              oldDispose = ui.Picture.onDispose;
          var created = 0, disposed = 0;
          ui.Picture.onCreate = (_) {
            created++;
            if (created != retireAt) {
              return;
            }
            if (retireCache) {
              cache.close();
            } else {
              j.close();
            }
          };
          ui.Picture.onDispose = (_) {
            disposed++;
          };
          try {
            expect(() => _finish(j), throwsStateError);
          } finally {
            ui.Picture.onCreate = oldCreate;
            ui.Picture.onDispose = oldDispose;
            j.close();
          }
          expect(created, retireAt);
          expect(disposed, retireAt);
          expect(cache.activeLeases, 0);
          expect(cache.preparedPictureCount, 0);
        },
      );
    }
  }

  test('owner retirement blocks paint, source queries and ready transfer', () {
    final c = EmphasisAllocationFixture(), a = _allocate(c, c.row(0));
    var active = true;
    void owner() {
      if (!active) throw StateError('Retired');
    }

    final j = _job(c, a, owner: owner);
    while (!j.isReady) {
      j.advance(maxParts: 17);
    }
    active = false;
    expect(j.takeLayout, throwsStateError);
    expect(c.cache.activeLeases, 2);
    active = true;
    final visible = _finish(_job(c, a, owner: owner));
    active = false;
    expect(() => visible.sourceAt(Offset.zero), throwsStateError);
    expect(() => visible.selectionBoxes(0, 1), throwsStateError);
    final recorder = ui.PictureRecorder();
    expect(
      () => visible.paint(Canvas(recorder), Offset.zero),
      throwsStateError,
    );
    recorder.endRecording().dispose();
    visible.close();
    expect(c.cache.activeLeases, 2);
  });
}
