import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(35, 40),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 30,
  ),
];
const _prefix =
    '<span style="font-size:31px">é</span><span style="font-size:18px;text-emphasis:triangle blue">汉</span>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 25 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

final class _CallbackIterable extends Iterable<ForumBodyNativeParagraphLease> {
  _CallbackIterable(this.callback);
  final void Function() callback;
  @override
  Iterator<ForumBodyNativeParagraphLease> get iterator {
    callback();
    return const <ForumBodyNativeParagraphLease>[].iterator;
  }
}

ForumBodyInlineEmphasisTextInput _source({
  String prefix = _prefix,
  String suffix = 'Z',
  TextDirection direction = TextDirection.ltr,
}) {
  final original = mixedInlineInput(
    prefix: prefix,
    suffix: suffix,
    direction: direction.name,
    paragraphStyle: 'text-emphasis:circle red;line-height:.4',
  ).content;
  final job = ForumBodyInlineEmphasisTextPreparation(
    content: original,
    ensureOwner: () {},
  );
  try {
    while (!job.isReady) {
      job.advance(maxParts: 1);
    }
    return job.takeInput();
  } finally {
    job.close();
  }
}

ForumBodyParagraphCache _cache({int entries = 8}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

typedef _Fixture = ({
  ForumBodyInlineEmphasisTextGeometry geometry,
  ForumBodyInlineParagraphRequest request,
  ForumBodyInlineParagraphLease parent,
});

_Fixture _fixture(
  ForumBodyParagraphCache cache, {
  ForumBodyInlineEmphasisTextInput? source,
  TextScaler scaler = const _Curve(),
  double width = 300,
}) {
  final input = source ?? _source();
  final request = ForumBodyInlineParagraphRequest(
    content: input.glyphInput.glyphs,
    dimensions: _dimensions,
  );
  final parent = request.acquire(
    cache,
    width: width,
    textScaler: scaler,
    cachedOnly: false,
  )!;
  final job = ForumBodyInlineEmphasisGeometryPreparation(
    input: input,
    parent: parent,
    ensureOwner: () {},
  );
  try {
    while (!job.isReady) {
      job.advance(maxParts: 1);
    }
    return (geometry: job.takeGeometry(), request: request, parent: parent);
  } catch (_) {
    parent.release();
    rethrow;
  } finally {
    job.close();
  }
}

ForumBodyInlineEmphasisFontPreparation _job(
  _Fixture f,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = const _Curve(),
  double width = 300,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
  void Function()? guard,
  ForumBodyInlineParagraphRequest? request,
}) => ForumBodyInlineEmphasisFontPreparation(
  geometry: f.geometry,
  parentRequest: request ?? f.request,
  parent: f.parent,
  cache: cache,
  ensureOwner: guard ?? () {},
  expectedTextScaler: scaler,
  width: width,
  additionalOwnedLeases: owned,
);

({ForumBodyInlineEmphasisFontMetrics value, int parts}) _finish(
  ForumBodyInlineEmphasisFontPreparation job,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var parts = 0;
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(30000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = job.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
      expect(cache.layoutBuildCount - before.$1, step.nativeLayoutsBuilt);
      expect(step.picturesRecorded, 0);
      expect(cache.pictureBuildCount, before.$2);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(job.cacheMiss, isFalse);
      expect(job.nativeLeases, isEmpty);
      parts += step.partsPrepared;
    }
    expect(job.advance(maxParts: 1).partsPrepared, 0);
    return (value: job.takeMetrics(), parts: parts);
  } finally {
    job.close();
  }
}

List<Object> _values(ForumBodyInlineEmphasisFontMetrics value) => [
  value.effectiveScales,
  value.unitFonts,
  for (final f in value.fonts)
    [
      f.input,
      f.nativeInputIdentity,
      f.scaledFontSize,
      f.width,
      f.height,
      f.alphabeticBaseline,
      f.fontBounds,
    ],
];
ForumBodyParagraphLease _blocker(ForumBodyParagraphCache cache, _Fixture f) =>
    cache.acquire(
      content: ForumBodyParagraphContent.anonymousInline(
        identity: f.parent.content.identity,
        fontRevision: 'external',
        styleRevision: f.parent.content.styleRevision,
        style: f.parent.content.style,
      ),
      width: 100,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      test(
        'actual full/half samples and native marker numerics $direction/$scaler',
        () {
          final cache = _cache(),
              f = _fixture(
                cache,
                source: _source(direction: direction),
                scaler: scaler,
              );
          addTearDown(f.parent.release);
          final calls = <double, int>{};
          final counted = _CallbackScaler((size) {
            calls.update(size, (n) => n + 1, ifAbsent: () => 1);
            return scaler.scale(size);
          });
          final value = _finish(_job(f, cache, scaler: counted), cache).value;
          expect(value.geometry, same(f.geometry));
          expect(value.parentRequest, same(f.request));
          expect(value.fonts, hasLength(3));
          expect(value.unitFonts, [0, 1, 2]);
          expect(calls, {
            for (final s in [20.0, 31.0, 18.0, 15.5, 9.0, 10.0]) s: 1,
          });
          expect(value.effectiveScales, {
            for (final s in calls.keys) s: scaler.scale(s),
          });
          expect(
            _values(
              _finish(_job(f, cache, scaler: scaler), cache, quantum: 7).value,
            ),
            _values(value),
          );
          for (final font in value.fonts) {
            expect(
              font.scaledFontSize,
              scaler.scale(font.input.textStyle.fontSize!),
            );
            final reference = TextPainter(
              text: TextSpan(
                text: font.input.mark,
                style: font.input.textStyle,
              ),
              textDirection: direction,
              locale: font.input.textStyle.locale,
              textScaler: value.textScaler,
            )..layout(maxWidth: double.infinity);
            try {
              var bounds = Rect.fromLTWH(
                0,
                0,
                reference.width,
                reference.height,
              );
              for (final b in reference.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: font.input.mark.length,
                ),
              )) {
                bounds = bounds.expandToInclude(b.toRect());
              }
              expect(font.width, reference.width);
              expect(font.height, reference.height);
              expect(
                font.alphabeticBaseline,
                reference.computeLineMetrics().single.baseline,
              );
              expect(font.fontBounds, bounds);
            } finally {
              reference.dispose();
            }
            final lease = font.request.acquire(
              cache,
              width: 300,
              textScaler: value.textScaler,
              cachedOnly: true,
            )!;
            try {
              expect(lease.nativeInputIdentity, font.nativeInputIdentity);
            } finally {
              lease.release();
            }
          }
          expect(cache.activeLeases, 1);
          expect(() => value.fonts.clear(), throwsUnsupportedError);
          expect(() => value.unitFonts.clear(), throwsUnsupportedError);
          expect(() => value.effectiveScales.clear(), throwsUnsupportedError);
          expect(value.fontForUnit(0), same(value.fonts[0]));
          expect(() => value.fontForUnit(-1), throwsRangeError);
          f.parent.release();
          cache.clearUnpinned();
          expect(cache.activeLeases, 0);
          expect(value.fonts.first.height, greaterThan(0));
        },
      );
    }
  }
  test('equal natural marker inputs share one font across runs and sides', () {
    final cache = _cache(),
        f = _fixture(
          cache,
          source: _source(
            prefix:
                '<span style="text-emphasis-position:over">A</span><span style="text-emphasis-position:under">B</span>',
          ),
        );
    addTearDown(f.parent.release);
    final value = _finish(_job(f, cache), cache).value;
    expect(value.fonts, hasLength(1));
    expect(value.unitFonts, [0, 0, 0]);
  });
  test('many distinct temporary fonts fit a parent plus one font slot', () {
    final cache = _cache(entries: 2), f = _fixture(cache);
    addTearDown(f.parent.release);
    final before = cache.layoutBuildCount;
    final value = _finish(_job(f, cache), cache).value;
    expect(value.fonts, hasLength(3));
    expect(cache.layoutBuildCount - before, 3);
    expect(cache.activeLeases, 1);
    expect(cache.entryCount, lessThanOrEqualTo(2));
  });
  test(
    'cached-only miss does no native work and resumes the same sampled input',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      final job = _job(f, cache), before = cache.layoutBuildCount;
      for (var n = 0; !job.cacheMiss; n++) {
        expect(n, lessThan(1000));
        final s = job.advance(maxParts: 1, cachedOnly: true);
        expect(s.nativeLayoutsBuilt, 0);
        expect(s.picturesRecorded, 0);
        expect(s.waitingForLayoutBudget, isFalse);
      }
      expect(cache.layoutBuildCount, before);
      expect(cache.activeLeases, 1);
      final value = _finish(job, cache).value;
      final warmBefore = cache.layoutBuildCount;
      expect(
        _values(_finish(_job(f, cache), cache, cachedOnly: true).value),
        _values(value),
      );
      expect(cache.layoutBuildCount, warmBefore);
    },
  );
  test(
    'requested full scaling or parent dimensions cannot be hidden by an owned prefix',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      for (final mode in [0, 1, 2]) {
        var prefixes = 0;
        final before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        );
        final request = mode == 2
            ? ForumBodyInlineParagraphRequest(
                content: f.request.content,
                dimensions: [
                  const PlaceholderDimensions(
                    size: Size(36, 40),
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    baselineOffset: 30,
                  ),
                ],
              )
            : f.request;
        final work = _job(
          f,
          cache,
          request: request,
          width: mode == 1 ? 301 : 300,
          scaler: mode == 0 ? TextScaler.noScaling : const _Curve(),
          owned: () {
            prefixes++;
            return [f.parent];
          },
        );
        expect(
          () => _finish(work, cache),
          throwsA(
            isA<ForumBodyEmphasisLineException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyEmphasisLineFailure.metrics,
            ),
          ),
        );
        expect(prefixes, 0);
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.activeLeases,
        ), before);
      }
    },
  );
  test(
    'changed half-only sampling reuses the actual parent but changes its font key',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      final a = _finish(_job(f, cache), cache).value;
      final changed = _CallbackScaler(
        (s) => const _Curve().scale(s) + (s == 15.5 ? 3 : 0),
      );
      final b = _finish(_job(f, cache, scaler: changed), cache).value;
      expect(a.geometry.nativeInputIdentity, b.geometry.nativeInputIdentity);
      expect(
        a.fonts[0].nativeInputIdentity,
        isNot(b.fonts[0].nativeInputIdentity),
      );
      expect(b.fonts[0].scaledFontSize, a.fonts[0].scaledFontSize + 3);
      expect(a.fonts[1].nativeInputIdentity, b.fonts[1].nativeInputIdentity);
    },
  );
  test(
    'foreign source, geometry key and cache owner are rejected before font work',
    () {
      final cache = _cache(), f = _fixture(cache), other = _fixture(cache);
      addTearDown(f.parent.release);
      addTearDown(other.parent.release);
      expect(
        f.parent.nativeInputIdentity,
        same(other.parent.nativeInputIdentity),
      );
      expect(
        () => _job(f, cache, request: other.request),
        throwsA(
          isA<ForumBodyEmphasisLineException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisLineFailure.source,
          ),
        ),
      );
      final resized = f.request.acquire(
        cache,
        width: 200,
        textScaler: const _Curve(),
        cachedOnly: false,
      )!;
      addTearDown(resized.release);
      expect(
        () => ForumBodyInlineEmphasisFontPreparation(
          geometry: f.geometry,
          parentRequest: f.request,
          parent: resized,
          cache: cache,
          ensureOwner: () {},
          expectedTextScaler: const _Curve(),
          width: 200,
        ),
        throwsA(
          isA<ForumBodyEmphasisLineException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisLineFailure.metrics,
          ),
        ),
      );
      final foreignCache = _cache();
      expect(() => _job(f, foreignCache), throwsStateError);
      expect(cache.activeLeases, 3);
    },
  );
  test('external pin wait keeps state and releases only temporary fonts', () {
    final cache = _cache(entries: 2),
        f = _fixture(cache),
        pin = _blocker(cache, f);
    addTearDown(f.parent.release);
    addTearDown(pin.release);
    final work = _job(f, cache);
    final before = cache.layoutBuildCount;
    var waiting = false;
    for (var n = 0; !waiting; n++) {
      expect(n, lessThan(1000));
      waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
    }
    expect(cache.layoutBuildCount, before);
    expect(cache.activeLeases, 2);
    final same = work.advance(maxParts: 7);
    expect(same.partsPrepared, 0);
    expect(same.waitingForLayoutBudget, isTrue);
    pin.release();
    expect(_finish(work, cache).value.fonts, hasLength(3));
    expect(cache.activeLeases, 1);
  });
  for (final refreshing in [false, true]) {
    test(
      'owned prefix impossibility fails without waiting refresh=$refreshing',
      () {
        final cache = _cache(entries: 2),
            f = _fixture(cache),
            pin = _blocker(cache, f);
        addTearDown(f.parent.release);
        addTearDown(pin.release);
        var calls = 0;
        final work = _job(
          f,
          cache,
          owned: () {
            calls++;
            return refreshing && calls == 1 ? [] : [pin, f.parent, pin];
          },
        );
        final before = cache.layoutBuildCount;
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
        expect(cache.layoutBuildCount, before);
        expect(cache.activeLeases, 2);
        if (refreshing) expect(calls, greaterThanOrEqualTo(2));
      },
    );
  }
  test('one total slot rejects a font before native acquisition', () {
    final cache = _cache(entries: 1), f = _fixture(cache);
    addTearDown(f.parent.release);
    final before = cache.layoutBuildCount;
    expect(
      () => _finish(_job(f, cache), cache),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect(cache.layoutBuildCount, before);
    expect(cache.activeLeases, 1);
  });
  test(
    'zero targets capture only actual parent samples and acquire no fonts',
    () {
      final cache = _cache(),
          f = _fixture(
            cache,
            source: _source(prefix: '', suffix: ''),
          );
      addTearDown(f.parent.release);
      final before = cache.layoutBuildCount,
          value = _finish(_job(f, cache), cache).value;
      expect(value.fonts, isEmpty);
      expect(value.unitFonts, isEmpty);
      expect(value.effectiveScales.keys, [20.0]);
      expect(cache.layoutBuildCount, before);
      expect(cache.activeLeases, 1);
    },
  );
  test(
    'all work and ready boundaries preserve caller leases on retirement',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      final parts = _finish(_job(f, cache), cache).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = _job(
          f,
          cache,
          guard: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        if (work.isReady) {
          expect(work.takeMetrics, throwsStateError);
        } else {
          expect(() => work.advance(maxParts: 1), throwsStateError);
        }
        expect(work.isReady, isFalse);
        work.close();
        expect(cache.activeLeases, 1);
        expect(work.nativeLeases, isEmpty);
      }
    },
  );
  test(
    'a scaler can retire preparation without triggering font acquisition',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      late ForumBodyInlineEmphasisFontPreparation work;
      work = _job(
        f,
        cache,
        scaler: _CallbackScaler((s) {
          work.close();
          return const _Curve().scale(s);
        }),
      );
      final before = cache.layoutBuildCount;
      expect(() => work.advance(maxParts: 100), throwsStateError);
      expect(cache.layoutBuildCount, before);
      expect(cache.activeLeases, 1);
    },
  );
  test('retirement with a temporary font in hand releases it exactly once', () {
    final cache = _cache(), f = _fixture(cache);
    addTearDown(f.parent.release);
    var armed = false;
    late ForumBodyInlineEmphasisFontPreparation work;
    work = _job(
      f,
      cache,
      guard: () {
        if (armed && work.nativeLeases.isNotEmpty) work.close();
      },
    );
    armed = true;
    expect(() => _finish(work, cache), throwsStateError);
    expect(cache.activeLeases, 1);
    expect(f.parent.isActive, isTrue);
  });
  test(
    'prefix iterator creation and ready callbacks cannot resurrect retired work',
    () {
      final cache = _cache(), f = _fixture(cache);
      addTearDown(f.parent.release);
      for (final mode in [0, 1, 2]) {
        var armed = false;
        late ForumBodyInlineEmphasisFontPreparation work;
        work = _job(
          f,
          cache,
          owned: mode == 0 ? () => _CallbackIterable(work.close) : null,
          guard: () {
            if (!armed) return;
            if (mode == 1) {
              work.advance(maxParts: 1);
            } else if (mode == 2 && work.isReady) {
              work.close();
            }
          },
        );
        armed = true;
        expect(() => _finish(work, cache), throwsStateError);
        expect(cache.activeLeases, 1);
        expect(work.nativeLeases, isEmpty);
      }
    },
  );
}
