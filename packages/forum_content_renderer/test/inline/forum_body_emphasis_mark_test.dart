import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _ink = Color(0xff123456);
ForumBodyResolvedStyle _style({
  TextStyle text = const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    color: _ink,
  ),
  ForumBodyTextEmphasis emphasis = const ForumBodyTextEmphasis(
    shape: ForumBodyEmphasisShape.dot,
  ),
  TextDirection direction = TextDirection.ltr,
  bool hidden = false,
}) => ForumBodyResolvedStyle(
  textStyle: text,
  textEmphasis: emphasis,
  role: ForumBodyTextRole.body,
  textAlign: TextAlign.start,
  textDirection: direction,
  visibilityHidden: hidden,
);
ForumBodyEmphasisMarkInput _input({
  ForumBodyResolvedStyle? style,
  String revision = 'mark-font-1',
  int styleRevision = 14,
}) => ForumBodyEmphasisMarkInput(
  style: style ?? _style(),
  fontRevision: revision,
  styleRevision: styleRevision,
);
ForumBodyParagraphCache _cache({int entries = 16, int bytes = 1 << 20}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

final class _Scaler extends TextScaler {
  _Scaler(this.sample);
  final double Function(double) sample;
  final calls = <double>[];
  @override
  double scale(double fontSize) {
    calls.add(fontSize);
    return sample(fontSize);
  }

  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

Future<List<int>> _pixels(void Function(Canvas) draw, int dpr) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(100 * dpr, 60 * dpr);
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
    final file = File('test/fixtures/fonts/language.ttf');
    await (FontLoader('ForumBodyLanguageTest')
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
        .load();
  });
  test('mark font settings exclude body boxes/spacing/decorations', () {
    final source = TextStyle(
      fontFamily: 'Imported',
      fontFamilyFallback: const ['Fallback'],
      package: 'fixture',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
      locale: const Locale('ja'),
      color: _ink,
      height: 4,
      letterSpacing: 7,
      wordSpacing: 8,
      backgroundColor: const Color(0xff00ff00),
      decoration: TextDecoration.underline,
      fontFeatures: const [
        FontFeature.disable('kern'),
        FontFeature.disable('ruby'),
      ],
      fontVariations: const [FontVariation('wght', 550)],
      shadows: const [Shadow(color: _ink, offset: Offset(1, 2))],
    );
    final input = _input(style: _style(text: source));
    final mark = input.textStyle;
    expect(mark.fontFamily, source.fontFamily);
    expect(mark.fontFamilyFallback, source.fontFamilyFallback);
    expect(mark.fontSize, 10);
    expect(mark.fontWeight, FontWeight.w700);
    expect(mark.fontStyle, FontStyle.italic);
    expect(mark.locale, const Locale('ja'));
    expect(mark.fontFeatures, const [
      FontFeature.disable('kern'),
      FontFeature.enable('ruby'),
    ]);
    expect(mark.fontVariations, source.fontVariations);
    expect(mark.shadows, source.shadows);
    expect(mark.color, _ink);
    expect(mark.height, kTextHeightNone);
    expect(mark.background, isNull);
    expect(mark.backgroundColor, isNull);
    expect(mark.foreground, isNull);
    expect(mark.letterSpacing, isNull);
    expect(mark.wordSpacing, isNull);
    expect(mark.decoration, TextDecoration.none);
    expect(source.height, 4);
    expect(source.fontFeatures!.last, const FontFeature.disable('ruby'));
  });
  test(
    'native input freezes caller lists and resolves currentColor by value',
    () {
      final features = [const FontFeature.disable('kern')];
      final variations = [const FontVariation('wght', 600)];
      final fallback = ['Fallback'];
      final shadows = [const Shadow(color: _ink)];
      final paint = Paint()..color = _ink;
      final paintedColor = paint.color;
      final input = _input(
        style: _style(
          text: TextStyle(
            fontSize: 20,
            foreground: paint,
            fontFeatures: features,
            fontVariations: variations,
            fontFamilyFallback: fallback,
            shadows: shadows,
          ),
        ),
      );
      final hash = input.hashCode;
      final bytes = input.estimatedInputBytes;
      features.clear();
      variations.clear();
      fallback.clear();
      shadows.clear();
      paint.color = const Color(0xffff0000);
      expect(input.textStyle.color, paintedColor);
      expect(input.textStyle.color!.toARGB32(), _ink.toARGB32());
      expect(input.textStyle.fontFeatures, hasLength(2));
      expect(input.textStyle.fontVariations, hasLength(1));
      expect(input.textStyle.fontFamilyFallback, ['Fallback']);
      expect(input.textStyle.shadows, hasLength(1));
      expect(input.hashCode, hash);
      expect(input.estimatedInputBytes, bytes);
      expect(
        () => input.textStyle.fontFeatures!.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'explicit mark color and visibility do not inherit body backgrounds',
    () {
      final source = _style(
        emphasis: const ForumBodyTextEmphasis(
          shape: ForumBodyEmphasisShape.circle,
          color: Color(0xffabcdef),
        ),
      );
      expect(_input(style: source).textStyle.color, const Color(0xffabcdef));
      final transparent = _input(
        style: _style(
          emphasis: const ForumBodyTextEmphasis(
            shape: ForumBodyEmphasisShape.circle,
            color: Color(0x00000000),
          ),
        ),
      );
      expect(transparent.textStyle.color, const Color(0x00000000));
      final hidden = _input(
        style: _style(
          hidden: true,
          text: const TextStyle(fontSize: 20, shadows: [Shadow(color: _ink)]),
        ),
      );
      expect(hidden.textStyle.color, const Color(0x00000000));
      expect(hidden.textStyle.shadows, isEmpty);
      expect(hidden.textStyle.fontSize, 10);
    },
  );
  for (final direction in TextDirection.values) {
    for (final dpr in [1, 3]) {
      for (final mark in [
        '•',
        '◦',
        '●',
        '○',
        '◉',
        '◎',
        '▲',
        '△',
        '﹅',
        '﹆',
        'e\u0301',
        '👩‍👩‍👧‍👦',
      ]) {
        test(
          'native mark $mark $direction DPR$dpr matches independent painter',
          () async {
            final cache = _cache();
            final input = _input(
              style: _style(
                direction: direction,
                emphasis: ForumBodyTextEmphasis(
                  shape: ForumBodyEmphasisShape.custom,
                  customMark: mark,
                ),
              ),
            );
            final lease = cache.acquireEmphasisMark(input: input);
            final reference = TextPainter(
              text: TextSpan(
                text: mark,
                style: const TextStyle(
                  inherit: false,
                  fontFamily: 'Ahem',
                  fontSize: 10,
                  color: _ink,
                  height: kTextHeightNone,
                  decoration: TextDecoration.none,
                  fontFeatures: [FontFeature.enable('ruby')],
                ),
              ),
              textDirection: direction,
            )..layout(maxWidth: double.infinity);
            addTearDown(reference.dispose);
            final layout = lease.layout;
            expect(layout.width, reference.width);
            expect(layout.height, reference.height);
            expect(
              layout.alphabeticBaseline,
              reference.computeLineMetrics().single.baseline,
            );
            final builds = cache.layoutBuildCount;
            expect(
              await _pixels((c) => layout.paint(c, const Offset(20, 20)), dpr),
              await _pixels(
                (c) => reference.paint(c, const Offset(20, 20)),
                dpr,
              ),
            );
            expect(cache.layoutBuildCount, builds);
            expect(cache.pictureBuildCount, 0);
            final Object handle = lease;
            expect(handle, isNot(isA<ForumBodyTextLease>()));
            lease.release();
            expect(() => lease.layout, throwsStateError);
            cache.clearUnpinned();
            expect(layout.isDisposed, isTrue);
            expect(cache.entryCount, 0);
            expect(cache.estimatedRetainedBytes, 0);
          },
        );
      }
    }
  }
  test(
    'nonlinear scaling samples the half size once and freezes native work',
    () {
      final cache = _cache();
      final scaler = _Scaler((size) => size < 15 ? size + 4 : size * 1.8);
      final input = _input(
        style: _style(
          emphasis: const ForumBodyTextEmphasis(
            shape: ForumBodyEmphasisShape.custom,
            customMark: 'X',
          ),
        ),
      );
      final lease = cache.acquireEmphasisMark(input: input, textScaler: scaler);
      expect(scaler.calls, [10]);
      expect(lease.layout.width, 14);
      expect(lease.layout.width, isNot(18));
      lease.release();
      final alias = cache.tryAcquireEmphasisMarkCached(
        input: input,
        textScaler: scaler,
      )!;
      expect(scaler.calls, [10, 10]);
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 1);
      alias.release();
    },
  );
  test('real ruby feature and locale affect the selected native glyph', () {
    final cache = _cache();
    final widths = <double>[];
    for (final locale in [
      const Locale('en'),
      const Locale('ja'),
      const Locale('ko'),
    ]) {
      final input = _input(
        style: _style(
          text: TextStyle(
            fontFamily: 'ForumBodyLanguageTest',
            fontSize: 20,
            locale: locale,
          ),
          emphasis: const ForumBodyTextEmphasis(
            shape: ForumBodyEmphasisShape.custom,
            customMark: '漢',
          ),
        ),
      );
      final plain = TextPainter(
        text: TextSpan(
          text: '漢',
          style: TextStyle(
            fontFamily: 'ForumBodyLanguageTest',
            fontSize: 10,
            locale: locale,
            fontFeatures: const [FontFeature.disable('ruby')],
          ),
        ),
        textDirection: TextDirection.ltr,
        locale: locale,
      )..layout();
      final mark = cache.acquireEmphasisMark(input: input);
      widths.add(mark.layout.width);
      expect(mark.layout.width * 2, plain.width);
      mark.release();
      plain.dispose();
    }
    expect(widths, [2.5, 3.75, 5]);
    expect(cache.layoutBuildCount, 3);
  });
  test(
    'paint-equivalent side changes reuse native input; real inputs invalidate',
    () {
      final cache = _cache();
      final original = _input();
      final first = cache.acquireEmphasisMark(input: original);
      first.release();
      final moved = _input(
        style: _style(
          emphasis: const ForumBodyTextEmphasis(
            shape: ForumBodyEmphasisShape.dot,
            side: ForumBodyEmphasisSide.under,
            verticalSide: ForumBodyEmphasisVerticalSide.left,
          ),
        ),
      );
      expect(moved, original);
      final hit = cache.acquireEmphasisMark(input: moved);
      expect(cache.layoutBuildCount, 1);
      hit.release();
      for (final input in [
        _input(revision: 'new-font'),
        _input(styleRevision: 15),
        _input(style: _style(direction: TextDirection.rtl)),
        _input(style: _style(text: const TextStyle(fontSize: 22))),
        _input(
          style: _style(
            emphasis: const ForumBodyTextEmphasis(
              shape: ForumBodyEmphasisShape.circle,
            ),
          ),
        ),
        _input(
          style: _style(
            emphasis: const ForumBodyTextEmphasis(
              shape: ForumBodyEmphasisShape.dot,
              color: Color(0xff0000ff),
            ),
          ),
        ),
      ]) {
        final lease = cache.acquireEmphasisMark(input: input);
        lease.release();
      }
      expect(cache.layoutBuildCount, 7);
      var delta = 1.0;
      final dynamicScaler = _Scaler((size) => size * delta);
      final warm = cache.acquireEmphasisMark(
        input: original,
        textScaler: dynamicScaler,
      );
      warm.release();
      delta = 1.25;
      final changed = cache.acquireEmphasisMark(
        input: original,
        textScaler: dynamicScaler,
      );
      expect(cache.layoutBuildCount, 8);
      changed.release();
    },
  );
  test(
    'pure request/probe deduplicate the same resource including a live alias',
    () {
      final cache = _cache(entries: 1);
      final request = ForumBodyEmphasisMarkRequest(_input());
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      request.includeBudget(probe, width: 0, textScaler: TextScaler.noScaling);
      request.includeBudget(
        probe,
        width: 100,
        textScaler: TextScaler.noScaling,
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
      final estimates = probe.snapshotNativeEstimates();
      expect(estimates, hasLength(1));
      expect(
        estimates.single.estimatedBytes,
        request.input.estimatedInputBytes + 112,
      );
      expect(
        request.acquire(
          cache,
          width: 0,
          textScaler: TextScaler.noScaling,
          cachedOnly: true,
        ),
        isNull,
      );
      final lease = request.acquire(
        cache,
        width: 100,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      probe.includeLease(lease);
      expect(probe.snapshotNativeIdentities(), {lease.nativeInputIdentity});
      expect(cache.estimatedRetainedBytes, estimates.single.estimatedBytes);
      probe.close();
      lease.release();
      cache.close();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
      expect(() => lease.layout, throwsStateError);
    },
  );
  test(
    'known geometry budget rejects before shaping and external pins can release',
    () {
      final input = _input();
      final tooSmall = _cache(bytes: input.estimatedInputBytes + 111);
      expect(
        () => tooSmall.acquireEmphasisMark(input: input),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(tooSmall.layoutBuildCount, 0);
      final cache = _cache(entries: 1);
      final pin = cache.acquireEmphasisMark(input: input);
      final next = _input(revision: 'next-font');
      expect(
        () => cache.acquireEmphasisMark(input: next),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 1);
      pin.release();
      final lease = cache.acquireEmphasisMark(input: next);
      expect(cache.layoutBuildCount, 2);
      expect(cache.entryCount, 1);
      lease.release();
    },
  );
  test(
    'warm hits validate scales, and scaler cancellation cannot refill owner',
    () {
      final input = _input();
      final cache = _cache();
      cache.acquireEmphasisMark(input: input).release();
      for (final value in [0.0, -1.0, double.nan, double.infinity, 4097.0]) {
        expect(
          () => cache.tryAcquireEmphasisMarkCached(
            input: input,
            textScaler: _Scaler((_) => value),
          ),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.scale,
            ),
          ),
        );
      }
      expect(cache.layoutBuildCount, 1);
      final cancel = _Scaler((size) {
        cache.close();
        return size;
      });
      expect(
        () => cache.acquireEmphasisMark(input: input, textScaler: cancel),
        throwsStateError,
      );
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );
  test('probe cancellation during sampling cannot install an identity', () {
    final cache = _cache();
    final probe = cache.createBudgetProbe();
    final scaler = _Scaler((size) {
      probe.close();
      return size;
    });
    expect(
      () => probe.includeEmphasisMark(input: _input(), textScaler: scaler),
      throwsStateError,
    );
    expect(cache.layoutBuildCount, 0);
    expect(cache.entryCount, 0);
  });
  test(
    'invalid custom marks and unresolved fonts fail before native allocation',
    () {
      for (final mark in [
        '',
        'AB',
        'A\u0301B',
        '\n',
        '\r',
        '\u2028',
        'A${'\u0301' * 512}',
      ]) {
        expect(
          () => _input(
            style: _style(
              emphasis: ForumBodyTextEmphasis(
                shape: ForumBodyEmphasisShape.custom,
                customMark: mark,
              ),
            ),
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => _input(style: _style(emphasis: const ForumBodyTextEmphasis())),
        throwsArgumentError,
      );
      for (final size in [
        null,
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.minPositive,
      ]) {
        expect(
          () => _input(
            style: _style(text: TextStyle(fontSize: size)),
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => _input(
          style: _style(
            text: TextStyle(
              fontSize: 20,
              fontFeatures: List.filled(513, const FontFeature.enable('kern')),
            ),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
