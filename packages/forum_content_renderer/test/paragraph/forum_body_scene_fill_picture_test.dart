import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphCache _cache({int entries = 32, int bytes = 1 << 24}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(c.close);
  return c;
}

ForumBodyTextPictureInput _fill({Color color = const Color(0x6644aa22)}) =>
    ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fillRect(
          rect: const Rect.fromLTWH(1.25, 2.75, 35.5, 17.25),
          color: color,
        ),
      ],
    );
ForumBodyTextPicturePreparation _work(
  ForumBodyParagraphCache c,
  ForumBodyTextPictureInput input, {
  Iterable<ForumBodyTextPictureLease> pictures = const [],
  void Function()? owner,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
  bool immediate = false,
}) => immediate
    ? ForumBodyTextPicturePreparation(
        cache: c,
        input: input,
        text: const [],
        pictures: pictures,
        ensureOwner: owner ?? () {},
        additionalOwnedLeases: owned,
      )
    : ForumBodyTextPicturePreparation.cooperative(
        cache: c,
        input: input,
        text: const [],
        pictures: pictures,
        ensureOwner: owner ?? () {},
        additionalOwnedLeases: owned,
      );
({ForumBodyTextPictureLease picture, int parts}) _finish(
  ForumBodyTextPicturePreparation w,
  ForumBodyParagraphCache c, {
  bool cachedOnly = false,
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !w.isReady; n++) {
      expect(n, lessThan(100000));
      final before = (c.layoutBuildCount, c.pictureBuildCount),
          step = w.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.picturesRecorded, lessThanOrEqualTo(1));
      expect(step.picturesRecorded, c.pictureBuildCount - before.$2);
      expect(c.layoutBuildCount, before.$1);
      expect(w.cacheMiss || step.waitingForLayoutBudget, isFalse);
      parts += step.partsPrepared;
    }
    return (picture: w.takeLease(), parts: parts);
  } finally {
    w.close();
  }
}

void _bind(ForumBodyTextPicturePreparation w) {
  for (var n = 0; !w.dependenciesReady; n++) {
    expect(n, lessThan(100000));
    final step = w.advance(maxParts: 1, cachedOnly: true);
    expect(step.partsPrepared, 1);
    expect(step.picturesRecorded, 0);
  }
}

Future<List<int>> _pixels(void Function(Canvas) draw, double dpr) async {
  final r = ui.PictureRecorder();
  draw(Canvas(r)..scale(dpr));
  final p = r.endRecording();
  try {
    final im = await p.toImage((220 * dpr).ceil(), (140 * dpr).ceil());
    try {
      return (await im.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      im.dispose();
    }
  } finally {
    p.dispose();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache c, int i) {
  final d = const ForumBodyParser().parse(
        html: '<p>fill-picture-pin$i</p>',
        sourceId: 'fill-picture-pin$i',
        conversionIdentity: 'none',
      ),
      styles = const ForumBodyStyleResolver().resolve(
        d,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: 'fill-pin',
          linkColor: const Color(0xff0000ff),
        ),
      ),
      p = c.acquire(
        content: const ForumBodyParagraphContentBuilder().build(
          document: d,
          path: '0',
          styles: styles,
        ),
        width: 300,
      );
  addTearDown(p.release);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final dpr in [1.0, 1.25, 3.0]) {
    for (final fit in [1.0, .7]) {
      test(
        'resource-free fill order, alpha and exact transforms $dpr/$fit',
        () async {
          final c = _cache();
          const rect = Rect.fromLTWH(2.25, 3.5, 60, 37.25),
              local = Offset(7.3, 11.9),
              outer = Offset(11.2, 5.1),
              color = Color.from(alpha: .37, red: .6, green: .2, blue: .8);
          final input = ForumBodyTextPictureInput(
                commands: [
                  ForumBodyTextPictureCommand.fillRect(
                    rect: const Rect.fromLTWH(0, 0, 100, 80),
                    color: const Color(0x6633aa11),
                  ),
                  ForumBodyTextPictureCommand.fillRect(
                    rect: rect,
                    color: color,
                    offset: local,
                    fitScale: fit,
                  ).translated(outer),
                ],
              ),
              before = c.layoutBuildCount,
              w = _work(c, input);
          _bind(w);
          expect(w.nativeLeases, isEmpty);
          final picture = _finish(w, c).picture;
          try {
            expect(input.commands.last.fill, (rect: rect, color: color));
            expect(input.commands.every((x) => x.isFill), isTrue);
            expect(input.nestingDepth, 0);
            final expected = await _pixels((cv) {
                  cv.drawRect(
                    const Rect.fromLTWH(0, 0, 100, 80),
                    Paint()..color = const Color(0x6633aa11),
                  );
                  cv.save();
                  cv.translate(outer.dx, outer.dy);
                  if (fit != 1) {
                    cv.translate(local.dx, local.dy);
                    cv.scale(fit);
                    cv.drawRect(rect, Paint()..color = color);
                  } else {
                    cv.drawRect(rect.shift(local), Paint()..color = color);
                  }
                  cv.restore();
                }, dpr),
                actual = await _pixels(
                  (cv) => picture.paint(cv, Offset.zero),
                  dpr,
                );
            expect(actual, orderedEquals(expected));
            expect(c.layoutBuildCount, before);
          } finally {
            picture.release();
          }
        },
      );

      test(
        'nested picture alias, fitting and source eviction $dpr/$fit',
        () async {
          final c = _cache(),
              child = _finish(_work(c, _fill()), c).picture,
              input = ForumBodyTextPictureInput(
                commands: [
                  ForumBodyTextPictureCommand.fillRect(
                    rect: const Rect.fromLTWH(0, 0, 100, 80),
                    color: const Color(0x44224499),
                  ),
                  ForumBodyTextPictureCommand.fromPicture(
                    child,
                    const Offset(30.3, 11.9),
                    fitScale: fit,
                  ).translated(const Offset(5.1, 2.2)),
                  ForumBodyTextPictureCommand.fromPicture(
                    child,
                    const Offset(11.1, 62.5),
                  ),
                ],
              ),
              reference = ui.PictureRecorder(),
              cv = Canvas(reference);
          cv.drawRect(
            const Rect.fromLTWH(0, 0, 100, 80),
            Paint()..color = const Color(0x44224499),
          );
          cv.save();
          cv.translate(5.1, 2.2);
          if (fit != 1) {
            cv.translate(30.3, 11.9);
            cv.scale(fit);
            child.paint(cv, Offset.zero);
          } else {
            child.paint(cv, const Offset(30.3, 11.9));
          }
          cv.restore();
          child.paint(cv, const Offset(11.1, 62.5));
          final expectedPicture = reference.endRecording(),
              w = _work(c, input, pictures: [child]);
          _bind(w);
          expect(w.nativeLeases, hasLength(1));
          child.release();
          final parent = _finish(w, c).picture;
          try {
            c.clearUnpinned();
            expect(c.entryCount, 1);
            expect(parent.input.nestingDepth, 1);
            expect(
              await _pixels((cv) => parent.paint(cv, Offset.zero), dpr),
              orderedEquals(
                await _pixels((cv) => cv.drawPicture(expectedPicture), dpr),
              ),
            );
          } finally {
            parent.release();
            expectedPicture.dispose();
          }
          expect(c.activeLeases, 0);
        },
      );
    }
  }

  test(
    'fill identity preserves floating color, order and resource-free accounting',
    () {
      const a = Color.from(alpha: .300000001, red: .2, green: .4, blue: .6),
          b = Color.from(alpha: .300000002, red: .2, green: .4, blue: .6);
      final first = _fill(color: a), second = _fill(color: b);
      expect(a.toARGB32(), b.toARGB32());
      expect(first, isNot(second));
      expect(_fill(color: a), first);
      expect(
        first.estimatedInputBytes,
        ForumBodyTextPictureInput.baseEstimatedInputBytes + 288,
      );
      expect(
        () => ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
          first.commands.single.nativeInputIdentity,
        ),
        throwsArgumentError,
      );
      expect(
        ForumBodyTextPictureInput(
          commands: [first.commands.single, second.commands.single],
        ),
        isNot(
          ForumBodyTextPictureInput(
            commands: [second.commands.single, first.commands.single],
          ),
        ),
      );
    },
  );

  test(
    'nested metadata and display retention charged once per actual picture key',
    () {
      final c = _cache(), child = _finish(_work(c, _fill()), c).picture;
      try {
        final cmd = ForumBodyTextPictureCommand.fromPicture(child, Offset.zero),
            one = ForumBodyTextPictureInput(commands: [cmd]),
            two = ForumBodyTextPictureInput(
              commands: [cmd, cmd.translated(const Offset(2, 3))],
            );
        expect(
          ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
            child.nativeInputIdentity,
          ),
          child.input.estimatedInputBytes + 16,
        );
        expect(
          one.estimatedPictureBytes,
          4096 + 256 + child.input.estimatedPictureBytes,
        );
        expect(two.estimatedPictureBytes - one.estimatedPictureBytes, 256 + 64);
        expect(two.estimatedInputBytes - one.estimatedInputBytes, 128 + 64);
        expect(one.nestingDepth, 1);
      } finally {
        child.release();
      }
    },
  );

  test(
    'invalid fill geometry and selectors are rejected without resource admission',
    () {
      for (final rect in [
        const Rect.fromLTRB(double.nan, 0, 1, 1),
        const Rect.fromLTRB(4, 0, 2, 1),
        const Rect.fromLTWH(32768, 0, 1, 1),
      ]) {
        expect(
          () => ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fillRect(
                rect: rect,
                color: const Color(0xff112233),
              ),
            ],
          ),
          throwsArgumentError,
        );
      }
      final fill = _fill().commands.single;
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: fill.nativeInputIdentity,
              offset: Offset.zero,
              bandChildIndex: 0,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fillRect(
              rect: const Rect.fromLTWH(0, 0, 1, 1),
              color: const Color(0xff112233),
              fitScale: double.nan,
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'missing, foreign and unrequested pictures do not borrow authority from pure keys',
    () {
      final c = _cache(),
          other = _cache(),
          child = _finish(_work(c, _fill()), c).picture,
          foreign = _finish(_work(other, _fill()), other).picture,
          input = ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromPicture(child, Offset.zero),
            ],
          ),
          before = c.activeLeases;
      try {
        expect(child.nativeInputIdentity, foreign.nativeInputIdentity);
        expect(() => _work(c, input, immediate: true), throwsArgumentError);
        expect(
          () => _work(c, input, pictures: [foreign], immediate: true),
          throwsStateError,
        );
        expect(
          () => _work(c, _fill(), pictures: [child], immediate: true),
          throwsArgumentError,
        );
        expect(c.activeLeases, before);
        child.release();
        expect(
          () => _work(c, input, pictures: [child], immediate: true),
          throwsStateError,
        );
      } finally {
        child.release();
        foreign.release();
      }
    },
  );

  test(
    'cached-only miss retains nested alias then reuses exact parent picture',
    () {
      final c = _cache(),
          child = _finish(_work(c, _fill()), c).picture,
          input = ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromPicture(
                child,
                const Offset(3, 4),
              ),
            ],
          ),
          w = _work(c, input, pictures: [child]),
          before = (c.layoutBuildCount, c.pictureBuildCount);
      for (var n = 0; !w.cacheMiss; n++) {
        expect(n, lessThan(10000));
        w.advance(maxParts: 1, cachedOnly: true);
      }
      expect((c.layoutBuildCount, c.pictureBuildCount), before);
      expect(w.nativeLeases, hasLength(1));
      final first = _finish(w, c).picture,
          counts = (c.layoutBuildCount, c.pictureBuildCount),
          warm = _finish(
            _work(c, input, pictures: [child]),
            c,
            cachedOnly: true,
          ).picture;
      expect(warm.nativeInputIdentity, first.nativeInputIdentity);
      expect((c.layoutBuildCount, c.pictureBuildCount), counts);
      first.release();
      warm.release();
      child.release();
      expect(c.activeLeases, 0);
    },
  );

  test('all nesting levels are bounded before new native recording', () {
    final c = _cache(entries: 128, bytes: 1 << 26);
    var child = _finish(_work(c, _fill()), c).picture;
    try {
      for (
        var depth = 1;
        depth <= ForumBodyTextPictureInput.maximumNestingDepth;
        depth++
      ) {
        final input = ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromPicture(child, Offset.zero),
          ],
        );
        expect(input.nestingDepth, depth);
        final next = _finish(_work(c, input, pictures: [child]), c).picture;
        child.release();
        child = next;
        c.clearUnpinned();
      }
      final before = c.pictureBuildCount;
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromPicture(child, Offset.zero),
          ],
        ),
        throwsArgumentError,
      );
      expect(c.pictureBuildCount, before);
    } finally {
      child.release();
    }
  });

  test(
    'complete owned nested prefix fails; true external pins wait stably',
    () {
      final c = _cache(entries: 8),
          child = _finish(_work(c, _fill()), c).picture,
          pins = [for (var i = 0; i < 7; i++) _pin(c, i)],
          input = ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromPicture(
                child,
                const Offset(4, 5),
              ),
            ],
          ),
          before = (c.pictureBuildCount, c.activeLeases);
      expect(
        () => _finish(
          _work(c, input, pictures: [child], owned: () => [child, ...pins]),
          c,
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect((c.pictureBuildCount, c.activeLeases), before);
      final w = _work(c, input, pictures: [child], owned: () => [child]);
      for (var n = 0; ; n++) {
        expect(n, lessThan(10000));
        if (w.advance().waitingForLayoutBudget) break;
      }
      final stable = (c.pictureBuildCount, c.hitCount, c.activeLeases);
      for (var i = 0; i < 3; i++) {
        final step = w.advance();
        expect(step.partsPrepared, 0);
        expect(step.waitingForLayoutBudget, isTrue);
      }
      expect((c.pictureBuildCount, c.hitCount, c.activeLeases), stable);
      pins.first.release();
      _finish(w, c).picture.release();
      child.release();
    },
  );

  test(
    'each cancellation and alias adoption owner retirement releases only own pictures',
    () {
      final c = _cache(),
          child = _finish(_work(c, _fill()), c).picture,
          input = ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromPicture(
                child,
                const Offset(4, 5),
              ),
            ],
          ),
          full = _finish(_work(c, input, pictures: [child]), c);
      full.picture.release();
      for (var stop = 0; stop <= full.parts; stop++) {
        final w = _work(c, input, pictures: [child]);
        for (var n = 0; n < stop && !w.isReady; n++) {
          w.advance(maxParts: 1);
        }
        w.close();
        expect(c.activeLeases, 1, reason: 'stop $stop');
      }
      ForumBodyTextPicturePreparation? active;
      var retired = false;
      active = _work(
        c,
        input,
        pictures: [child],
        owner: () {
          if (active?.nativeLeases.isNotEmpty == true) {
            retired = true;
            active!.close();
          }
        },
      );
      expect(() => _finish(active!, c), throwsStateError);
      expect(retired, isTrue);
      expect(c.activeLeases, 1);
      child.release();
    },
  );
}
