import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _blue = Color(0xff0000ff), _red = Color(0xffff0000);

final class _Fixture {
  _Fixture({
    this.direction = TextDirection.ltr,
    int entries = 12,
    ForumBodyParagraphLayoutMode mode =
        ForumBodyParagraphLayoutMode.intrinsicSingleLine,
    double width = 400,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    final doc = const ForumBodyParser().parse(
      html: '<p>ffi é <span>العربية</span> 👩‍👩‍👧‍👦 中</p>',
      sourceId: 'mixed-emphasis-scene',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        textDirection: direction,
        fontRevision: 'ahem',
        linkColor: _blue,
      ),
    );
    content = const ForumBodyParagraphContentBuilder().build(
      document: doc,
      styles: styles,
      path: '0',
      layoutMode: mode,
    );
    base = cache.acquire(
      content: content,
      width: width,
      textScaler: textScaler,
    );
    ForumBodyEmphasisMarkLease mark(Color color) => cache.acquireEmphasisMark(
      input: ForumBodyEmphasisMarkInput(
        style: ForumBodyResolvedStyle(
          textStyle: content.style.textStyle,
          role: ForumBodyTextRole.body,
          textAlign: TextAlign.start,
          textDirection: direction,
          textEmphasis: ForumBodyTextEmphasis(
            shape: ForumBodyEmphasisShape.custom,
            customMark: 'X',
            color: color,
          ),
        ),
        fontRevision: 'ahem',
        styleRevision: styles.resolverRevision,
      ),
      textScaler: textScaler,
    );
    blue = mark(_blue);
    red = mark(_red);
    input = ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fromText(base, const Offset(5, 35)),
        ForumBodyTextPictureCommand.fromEmphasisMark(
          blue,
          const Offset(25, 10),
        ),
        ForumBodyTextPictureCommand.fromEmphasisMark(red, const Offset(90, 80)),
        ForumBodyTextPictureCommand.fromEmphasisMark(
          blue,
          const Offset(60, 10),
        ),
      ],
    );
    addTearDown(() {
      base.release();
      blue.release();
      red.release();
      cache.close();
    });
  }
  final TextDirection direction;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyParagraphContent content;
  late final ForumBodyParagraphLease base;
  late final ForumBodyEmphasisMarkLease blue, red;
  late final ForumBodyTextPictureInput input;
  ForumBodyTextPicturePreparation open() => ForumBodyTextPicturePreparation(
    cache: cache,
    input: input,
    text: [base],
    marks: [blue, red],
    ensureOwner: () {},
  );
  ForumBodyTextPictureLease finish(
    ForumBodyTextPicturePreparation job, {
    bool cachedOnly = false,
  }) {
    final builds = cache.layoutBuildCount;
    for (var i = 0; !job.isReady && i < 100; i++) {
      final step = job.advance(maxParts: 1, cachedOnly: cachedOnly);
      expect(step.partsPrepared, lessThanOrEqualTo(1));
      expect(step.picturesRecorded, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(job.cacheMiss, isFalse);
      expect(cache.layoutBuildCount, builds);
    }
    expect(job.isReady, isTrue);
    return job.takeLease();
  }
}

Future<List<int>> _pixels(void Function(Canvas) draw, int dpr) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(420 * dpr, 120 * dpr);
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

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.4 : fontSize * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final dpr in [1, 3]) {
      for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
        test('fitted base and marks $direction DPR$dpr $scaler', () async {
          final f = _Fixture(
            direction: direction,
            mode: ForumBodyParagraphLayoutMode.fitSingleLine,
            width: 80,
            textScaler: scaler,
          );
          final native = TextPainter(
            text: f.content.textSpan,
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: double.infinity);
          final marker = TextPainter(
            text: TextSpan(
              text: 'X',
              style: const TextStyle(
                inherit: false,
                fontFamily: 'Ahem',
                fontSize: 10,
                color: _blue,
                height: kTextHeightNone,
                decoration: TextDecoration.none,
                fontFeatures: [FontFeature.enable('ruby')],
              ),
            ),
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: double.infinity);
          addTearDown(() {
            native.dispose();
            marker.dispose();
          });
          final fitScale = 80 / native.width;
          expect(f.base.layout.paintScale, fitScale);
          final input = ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromText(f.base, const Offset(5, 35)),
              ForumBodyTextPictureCommand.fromEmphasisMark(
                f.blue,
                const Offset(25, 10),
                fitScale: f.base.layout.paintScale,
              ),
              // A following unscaled command detects leaked canvas transforms.
              ForumBodyTextPictureCommand.fromEmphasisMark(
                f.blue,
                const Offset(120, 35),
              ),
              ForumBodyTextPictureCommand.fromText(
                f.base,
                const Offset(25, 70),
                fitScale: .5,
              ),
            ],
          );
          final job = ForumBodyTextPicturePreparation(
            cache: f.cache,
            input: input,
            text: [f.base],
            marks: [f.blue],
            ensureOwner: () {},
          );
          f.base.release();
          f.blue.release();
          f.red.release();
          final scene = f.finish(job);
          addTearDown(scene.release);
          f.cache.clearUnpinned();
          expect(f.cache.entryCount, 1);
          final actual = await _pixels((c) => scene.paint(c, Offset.zero), dpr);
          final expected = await _pixels((c) {
            void fitted(TextPainter painter, Offset offset, double scale) {
              c.save();
              c.translate(offset.dx, offset.dy);
              c.scale(scale, scale);
              painter.paint(c, Offset.zero);
              c.restore();
            }

            fitted(native, const Offset(5, 35), fitScale);
            fitted(marker, const Offset(25, 10), fitScale);
            marker.paint(c, const Offset(120, 35));
            fitted(native, const Offset(25, 70), fitScale * .5);
          }, dpr);
          expect(actual, expected);
          final hits = f.cache.hitCount;
          final warm = f.cache.tryAcquireTextPicture(input);
          expect(warm, isNotNull);
          warm!.release();
          expect(f.cache.hitCount, hits + 1);
          final unscaled = ForumBodyTextPictureInput(
            commands: [
              for (final command in input.commands)
                ForumBodyTextPictureCommand(
                  nativeInputIdentity: command.nativeInputIdentity,
                  offset: command.offset,
                  bandChildIndex: command.bandChildIndex,
                ),
            ],
          );
          expect(unscaled, isNot(input));
          expect(f.cache.tryAcquireTextPicture(unscaled), isNull);
          expect(unscaled.estimatedBytes, input.estimatedBytes);
        });
      }
    }
  }
  test('invalid fit transforms fail before recording or cache mutation', () {
    final f = _Fixture();
    for (final scale in [0.0, -1.0, 1.01, double.nan, double.infinity]) {
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromEmphasisMark(
              f.blue,
              Offset.zero,
              fitScale: scale,
            ),
          ],
        ),
        throwsArgumentError,
      );
    }
    expect(f.cache.pictureBuildCount, 0);
    expect(f.cache.activeLeases, 3);
  });
  for (final direction in TextDirection.values) {
    for (final dpr in [1, 3]) {
      test(
        'mixed native text/mark scene $direction DPR$dpr survives glyph eviction',
        () async {
          final f = _Fixture(direction: direction);
          final native = TextPainter(
            text: f.content.textSpan,
            textDirection: direction,
          )..layout(maxWidth: double.infinity);
          TextPainter marker(Color color) => TextPainter(
            text: TextSpan(
              text: 'X',
              style: TextStyle(
                inherit: false,
                fontFamily: 'Ahem',
                fontSize: 10,
                color: color,
                height: kTextHeightNone,
                decoration: TextDecoration.none,
                fontFeatures: const [FontFeature.enable('ruby')],
              ),
            ),
            textDirection: direction,
          )..layout(maxWidth: double.infinity);
          final blue = marker(_blue), red = marker(_red);
          addTearDown(() {
            native.dispose();
            blue.dispose();
            red.dispose();
          });
          final job = f.open();
          f.base.release();
          f.blue.release();
          f.red.release();
          expect(f.cache.activeLeases, 3);
          final scene = f.finish(job);
          addTearDown(scene.release);
          f.cache.clearUnpinned();
          expect(f.cache.entryCount, 1);
          expect(f.cache.activeLeases, 1);
          expect(f.cache.preparedPictureCount, 1);
          final builds = f.cache.layoutBuildCount,
              pictures = f.cache.pictureBuildCount;
          final actual = await _pixels((c) => scene.paint(c, Offset.zero), dpr);
          final expected = await _pixels((c) {
            native.paint(c, const Offset(5, 35));
            blue.paint(c, const Offset(25, 10));
            red.paint(c, const Offset(90, 80));
            blue.paint(c, const Offset(60, 10));
          }, dpr);
          expect(actual, expected);
          expect(f.cache.layoutBuildCount, builds);
          expect(f.cache.pictureBuildCount, pictures);
          expect(f.content.projection.text, 'ffi é العربية 👩‍👩‍👧‍👦 中');
          f.cache.close();
          expect(f.cache.activeLeases, 0);
          expect(f.cache.estimatedRetainedBytes, 0);
          final retiredRecorder = ui.PictureRecorder();
          try {
            expect(
              () => scene.paint(Canvas(retiredRecorder), Offset.zero),
              throwsStateError,
            );
          } finally {
            retiredRecorder.endRecording().dispose();
          }
        },
      );
    }
  }
  test(
    'mark metadata is charged once per native resource, not per command',
    () {
      final f = _Fixture();
      final once = ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand.fromEmphasisMark(f.blue, Offset.zero),
        ],
      );
      final twice = ForumBodyTextPictureInput(
        commands: [
          ...once.commands,
          ForumBodyTextPictureCommand.fromEmphasisMark(
            f.blue,
            const Offset(20, 0),
          ),
        ],
      );
      expect(twice.estimatedInputBytes - once.estimatedInputBytes, 128);
      expect(
        once.estimatedInputBytes,
        greaterThan(f.blue.input.estimatedInputBytes),
      );
      final job = ForumBodyTextPicturePreparation(
        cache: f.cache,
        input: twice,
        text: const [],
        marks: [f.blue],
        ensureOwner: () {},
      );
      final scene = f.finish(job);
      expect(f.cache.activeLeases, 4);
      scene.release();
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: f.blue.nativeInputIdentity,
              offset: Offset.zero,
              bandChildIndex: 0,
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'missing, foreign and unused glyph handles roll back all private aliases',
    () {
      final f = _Fixture(), other = _Fixture();
      expect(f.blue.nativeInputIdentity, other.blue.nativeInputIdentity);
      for (final marks in <List<ForumBodyEmphasisMarkLease>>[
        [],
        [f.blue],
        [other.blue, f.red],
        [f.blue, f.red, f.red, f.red],
      ]) {
        expect(
          () => ForumBodyTextPicturePreparation(
            cache: f.cache,
            input: f.input,
            text: [f.base],
            marks: marks,
            ensureOwner: () {},
          ),
          throwsA(anyOf(isArgumentError, isStateError)),
        );
        expect(f.cache.activeLeases, 3);
        expect(other.cache.activeLeases, 3);
        expect(f.cache.pictureBuildCount, 0);
      }
    },
  );
  test(
    'cached-only miss records nothing and a hit reuses the exact mixed scene',
    () {
      final f = _Fixture();
      final cold = f.open();
      while (!cold.cacheMiss) {
        cold.advance(maxParts: 1, cachedOnly: true);
      }
      expect(cold.isReady, isFalse);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 6);
      cold.close();
      expect(f.cache.activeLeases, 3);
      final first = f.finish(f.open());
      final second = f.finish(f.open(), cachedOnly: true);
      expect(first.nativeInputIdentity, second.nativeInputIdentity);
      expect(f.cache.pictureBuildCount, 1);
      expect(f.cache.layoutBuildCount, 3);
      first.release();
      second.release();
    },
  );
  test(
    'external pins resume the same mixed draw transaction without reshaping',
    () {
      final f = _Fixture(entries: 4);
      final extra = f.cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: f.content.identity,
          fontRevision: f.content.fontRevision,
          styleRevision: f.content.styleRevision,
          style: f.content.style,
        ),
        width: 100,
      );
      addTearDown(extra.release);
      final job = f.open();
      var waiting = false;
      while (!waiting) {
        waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(job.input, same(f.input));
      expect(f.cache.pictureBuildCount, 0);
      final builds = f.cache.layoutBuildCount;
      final stopped = job.advance(maxParts: 1);
      expect(stopped.partsPrepared, 0);
      expect(stopped.waitingForLayoutBudget, isTrue);
      extra.release();
      final scene = f.finish(job);
      expect(f.cache.layoutBuildCount, builds);
      expect(f.cache.pictureBuildCount, 1);
      scene.release();
    },
  );
  for (final units in [0, 1, 3, 4, 5, 6, 7, 8, 9, 10]) {
    test(
      'mixed scene cancellation releases source and glyph aliases at $units',
      () {
        final f = _Fixture();
        final job = f.open();
        for (var i = 0; i < units && !job.isReady; i++) {
          job.advance(maxParts: 1);
        }
        job.close();
        job.close();
        expect(f.cache.activeLeases, 3);
        f.cache.clearUnpinned();
        expect(f.cache.entryCount, 3);
        expect(() => job.takeLease(), throwsStateError);
      },
    );
  }
  test(
    'native recording callback retirement does not install a mixed picture',
    () {
      final f = _Fixture();
      final job = f.open();
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => job.close();
      try {
        expect(() => f.finish(job), throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
        job.close();
      }
      expect(f.cache.activeLeases, 3);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.preparedPictureCount, 0);
    },
  );
}
