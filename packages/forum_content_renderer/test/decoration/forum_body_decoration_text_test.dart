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
  TextDirection direction = TextDirection.ltr,
  bool hidden = false,
}) => ForumBodyResolvedStyle(
  textStyle: text,
  role: ForumBodyTextRole.list,
  textAlign: TextAlign.start,
  textDirection: direction,
  visibilityHidden: hidden,
);
ForumBodyDecorationTextInput _input(
  String text, {
  ForumBodyResolvedStyle? style,
}) => ForumBodyDecorationTextInput.label(
  text: text,
  style: style ?? _style(),
  fontRevision: 'label-font',
  styleRevision: 17,
);
ForumBodyParagraphCache _cache({int entries = 16, int bytes = 1 << 22}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyDecorationTextLease? _acquire(
  ForumBodyParagraphCache cache,
  ForumBodyDecorationTextInput input, {
  bool cachedOnly = false,
  TextScaler scaler = TextScaler.noScaling,
}) => ForumBodyDecorationTextRequest(
  input,
).acquire(cache, width: 0, textScaler: scaler, cachedOnly: cachedOnly);

final class _Scaler extends TextScaler {
  _Scaler(this.sample);
  final double Function(double) sample;
  final calls = <double>[];
  @override
  double scale(double size) {
    calls.add(size);
    return sample(size);
  }

  @override
  double get textScaleFactor => throw StateError('Use real per-size scale');
}

Future<List<int>> _pixels(void Function(Canvas) draw, int dpr) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr * 1.0));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(256 * dpr, 96 * dpr);
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
    await (FontLoader('DecorationLanguageTest')..addFont(
          Future.value(
            ByteData.sublistView(
              File('test/fixtures/fonts/language.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });
  test(
    'labels use complete resolved font, without emphasis feature/half-size or body boxes',
    () {
      final input = _input(
        '12.',
        style: _style(
          text: const TextStyle(
            fontFamily: 'Imported',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            locale: Locale('ja'),
            color: _ink,
            height: 4,
            letterSpacing: 2,
            wordSpacing: 3,
            backgroundColor: Color(0xff00ff00),
            decoration: TextDecoration.underline,
            fontFeatures: [FontFeature.disable('kern')],
          ),
        ),
      );
      final style = input.textStyle;
      expect(style.fontFamily, 'Imported');
      expect(style.fontSize, 20);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontStyle, FontStyle.italic);
      expect(style.locale, const Locale('ja'));
      expect(style.fontFeatures, const [FontFeature.disable('kern')]);
      expect((style.letterSpacing, style.wordSpacing), (2.0, 3.0));
      expect(style.height, kTextHeightNone);
      expect(style.decoration, TextDecoration.none);
      expect(style.backgroundColor, isNull);
      expect(style.background, isNull);
      expect(input.mark, '12.');
      expect(input, isNot(isA<ForumBodyEmphasisMarkInput>()));
      expect(_style().textEmphasis.isEnabled, isFalse);
    },
  );

  test(
    'label font collections are frozen and hidden labels do not paint shadows',
    () {
      final fallbacks = ['Fallback'];
      final features = [const FontFeature.enable('kern')];
      final variations = [const FontVariation('wght', 500)];
      final shadows = [const Shadow(color: _ink)];
      final source = TextStyle(
        fontSize: 20,
        fontFamily: 'Imported',
        fontFamilyFallback: fallbacks,
        fontFeatures: features,
        fontVariations: variations,
        shadows: shadows,
      );
      final input = _input('a.', style: _style(text: source));
      final hash = input.hashCode, bytes = input.estimatedInputBytes;
      fallbacks.clear();
      features.clear();
      variations.clear();
      shadows.clear();
      expect(input.textStyle.fontFamilyFallback, ['Fallback']);
      expect(input.textStyle.fontFeatures, hasLength(1));
      expect(input.textStyle.fontVariations, hasLength(1));
      expect(input.textStyle.shadows, hasLength(1));
      expect(input.hashCode, hash);
      expect(input.estimatedInputBytes, bytes);
      expect(
        () => input.textStyle.fontFeatures!.clear(),
        throwsUnsupportedError,
      );
      final hidden = _input(
        'a.',
        style: _style(
          text: const TextStyle(fontSize: 20, shadows: [Shadow(color: _ink)]),
          hidden: true,
        ),
      );
      expect(hidden.textStyle.color, const Color(0x00000000));
      expect(hidden.textStyle.shadows, isEmpty);
    },
  );

  test(
    'decoration text is bounded and rejects breaks, invalid sizes and opaque paint before native work',
    () {
      for (final text in [
        '',
        List.filled(65, '1').join(),
        '1\n2',
        '1\r2',
        '1\u00852',
        '1\u20282',
        '1\u20292',
      ]) {
        expect(() => _input(text), throwsArgumentError, reason: text);
      }
      for (final text in [
        const TextStyle(),
        const TextStyle(fontSize: 0),
        TextStyle(fontSize: double.nan),
        TextStyle(fontSize: 20, foreground: Paint()),
        TextStyle(fontSize: 20, background: Paint()),
        TextStyle(
          fontSize: 20,
          fontFeatures: List.filled(513, const FontFeature.enable('kern')),
        ),
      ]) {
        expect(
          () => _input('1.', style: _style(text: text)),
          throwsArgumentError,
        );
      }
      final cache = _cache();
      final lease = _acquire(cache, _input(List.filled(64, '1').join()))!;
      expect(lease.layout.lineCount, 1);
      expect(cache.layoutBuildCount, 1);
      lease.release();
    },
  );

  test(
    'full font-size nonlinear sample joins common warm/probe accounting without source API',
    () {
      final cache = _cache();
      final input = _input('12.');
      final request = ForumBodyDecorationTextRequest(input);
      final scaler = _Scaler((size) => size < 15 ? size + 4 : size * 1.8);
      expect(_acquire(cache, input, cachedOnly: true, scaler: scaler), isNull);
      expect(cache.layoutBuildCount, 0);
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      request.includeBudget(probe, width: 0, textScaler: scaler);
      ForumBodyDecorationTextRequest(
        _input('12.'),
      ).includeBudget(probe, width: 0, textScaler: scaler);
      final estimates = probe.snapshotNativeEstimates();
      expect(estimates, hasLength(1));
      expect(cache.layoutBuildCount, 0);
      final lease = _acquire(cache, input, scaler: scaler)!;
      expect(scaler.calls.every((size) => size == 20), isTrue);
      expect(lease.layout.width, 108);
      expect(lease, isNot(isA<ForumBodyTextLease>()));
      expect(lease, isNot(isA<ForumBodyEmphasisMarkLease>()));
      probe.includeLease(lease);
      expect(probe.snapshotNativeIdentities(), {lease.nativeInputIdentity});
      final warm = _acquire(
        cache,
        _input('12.'),
        cachedOnly: true,
        scaler: scaler,
      )!;
      expect(warm.layout, same(lease.layout));
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 2);
      final layout = lease.layout;
      probe.close();
      cache.close();
      expect(layout.isDisposed, isTrue);
      expect(warm.isActive, isFalse);
      lease.release();
      warm.release();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'label requests cannot bypass shared content/pin budgets or revive retired owners',
    () {
      final cache = _cache(entries: 1);
      final first = _acquire(cache, _input('1.'))!;
      expect(
        () => _acquire(cache, _input('2.')),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 1);
      first.release();
      final second = _acquire(cache, _input('2.'))!;
      expect(cache.layoutBuildCount, 2);
      second.release();
      final small = _cache(bytes: 1);
      expect(
        () => _acquire(small, _input('1.')),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(small.layoutBuildCount, 0);
      final retired = _cache();
      final scaler = _Scaler((size) {
        retired.close();
        return size;
      });
      expect(
        () => _acquire(retired, _input('1.'), scaler: scaler),
        throwsStateError,
      );
      expect(retired.activeLeases, 0);
      expect(retired.estimatedRetainedBytes, 0);
    },
  );

  test(
    'page pictures adopt generic labels without source handles and retain only the recorded picture',
    () async {
      final cache = _cache();
      final label = _acquire(cache, _input('12.'))!;
      final input = ForumBodyTextPictureInput(
        commands: [
          for (final offset in [const Offset(20, 20), const Offset(100, 40)])
            ForumBodyTextPictureCommand.fromDecorationText(label, offset),
        ],
      );
      final work = ForumBodyTextPicturePreparation.cooperative(
        cache: cache,
        input: input,
        text: const [],
        marks: [label],
        ensureOwner: () {},
      );
      addTearDown(work.close);
      for (var i = 0; !work.dependenciesReady && i < 100; i++) {
        work.advance(maxParts: 1);
      }
      expect(work.dependenciesReady, isTrue);
      expect(
        work.nativeLeases.whereType<ForumBodyDecorationTextLease>(),
        hasLength(1),
      );
      label.release();
      for (var i = 0; !work.isReady && i < 100; i++) {
        final step = work.advance(maxParts: 1);
        expect(step.partsPrepared, lessThanOrEqualTo(1));
        expect(step.picturesRecorded, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      expect(work.isReady, isTrue);
      final picture = work.takeLease();
      addTearDown(picture.release);
      expect(cache.activeLeases, 1);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 1);
      final reference = TextPainter(
        text: TextSpan(text: '12.', style: _input('12.').textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      try {
        expect(
          await _pixels((c) => picture.paint(c, Offset.zero), 2),
          await _pixels((c) {
            reference.paint(c, const Offset(20, 20));
            reference.paint(c, const Offset(100, 40));
          }, 2),
        );
      } finally {
        reference.dispose();
      }
      cache.close();
      expect(picture.isActive, isFalse);
      picture.release();
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test('cancelled label picture preparation releases private font aliases', () {
    final cache = _cache();
    final label = _acquire(cache, _input('AA.'))!;
    final work = ForumBodyTextPicturePreparation(
      cache: cache,
      input: ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand.fromDecorationText(label, Offset.zero),
        ],
      ),
      text: const [],
      marks: [label],
      ensureOwner: () {},
    );
    label.release();
    expect(cache.activeLeases, 1);
    work.close();
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
    cache.clearUnpinned();
    expect(cache.entryCount, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });

  test(
    'real selected font locale retains ordinary forms without adding ruby substitution',
    () {
      final cache = _cache();
      for (final locale in [
        const Locale('en'),
        const Locale('ja'),
        const Locale('ko'),
      ]) {
        final source = TextStyle(
          inherit: false,
          fontFamily: 'DecorationLanguageTest',
          fontSize: 20,
          locale: locale,
          color: _ink,
          height: kTextHeightNone,
          decoration: TextDecoration.none,
        );
        final lease = _acquire(
          cache,
          _input('漢', style: _style(text: source)),
        )!;
        final reference = TextPainter(
          text: TextSpan(text: '漢', style: source),
          textDirection: TextDirection.ltr,
          locale: locale,
        )..layout();
        expect(lease.layout.width, reference.width);
        reference.dispose();
        lease.release();
      }
      expect(cache.layoutBuildCount, 3);
    },
  );

  for (final label in ['1.', '12.', 'a.', 'AA.', '•', '◦', '▪']) {
    for (final direction in TextDirection.values) {
      for (final dpr in [1, 3]) {
        test(
          'actual native label $label $direction DPR$dpr matches independent full-size painter',
          () async {
            final cache = _cache();
            final lease = _acquire(
              cache,
              _input(label, style: _style(direction: direction)),
            )!;
            final reference = TextPainter(
              text: TextSpan(
                text: label,
                style: const TextStyle(
                  inherit: false,
                  fontFamily: 'Ahem',
                  fontSize: 20,
                  color: _ink,
                  height: kTextHeightNone,
                  decoration: TextDecoration.none,
                ),
              ),
              textDirection: direction,
            )..layout(maxWidth: double.infinity);
            try {
              expect(lease.layout.width, reference.width);
              expect(lease.layout.height, reference.height);
              expect(
                lease.layout.alphabeticBaseline,
                reference.computeLineMetrics().single.baseline,
              );
              expect(
                await _pixels(
                  (c) => lease.layout.paint(c, const Offset(20, 20)),
                  dpr,
                ),
                await _pixels(
                  (c) => reference.paint(c, const Offset(20, 20)),
                  dpr,
                ),
              );
              expect(cache.layoutBuildCount, 1);
              expect(cache.pictureBuildCount, 0);
            } finally {
              reference.dispose();
              lease.release();
            }
          },
        );
      }
    }
  }
}
