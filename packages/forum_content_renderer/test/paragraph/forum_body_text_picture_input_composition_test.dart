import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

class _Fixture {
  _Fixture({bool band = false, int entries = 16}) {
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final doc = const ForumBodyParser().parse(
      html: '<p style="color:red">AB</p><p style="color:blue">xy</p>',
      sourceId: 'picture-composition',
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
        fontRevision: 'composition-ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final content = [
      for (final path in ['0', '1'])
        const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: styles,
          path: path,
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ];
    if (band) {
      final input = ForumBodyTextBandContent(contexts: content);
      text = [
        for (var i = 0; i < 2; i++)
          cache.acquireBandChild(content: input, childIndex: i),
      ];
      for (final lease in text.cast<ForumBodyTextBandChildLease>()) {
        cache.prepareBandChildPaint(lease);
      }
    } else {
      text = [
        for (final item in content) cache.acquire(content: item, width: 140),
      ];
    }
    a = ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fromText(
          text[0],
          const Offset(2, 3),
          fitScale: .63,
        ),
        ForumBodyTextPictureCommand.fromText(text[1], const Offset(40, 10)),
      ],
    );
    b = ForumBodyTextPictureInput(
      commands: [
        ForumBodyTextPictureCommand.fromText(
          text[1],
          const Offset(5, 55),
          fitScale: .75,
        ),
        ForumBodyTextPictureCommand.fromText(text[0], const Offset(60, 30)),
      ],
    );
  }
  late final ForumBodyParagraphCache cache;
  late final List<ForumBodyTextLease> text;
  late final ForumBodyTextPictureInput a, b;
}

ForumBodyTextPictureInput _finish(ForumBodyTextPictureInputComposition job) {
  addTearDown(job.close);
  for (var part = 0; !job.isReady && part < 100000; part++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  return job.takeInput();
}

void _draw(Canvas canvas, _Fixture f, ForumBodyTextPictureInput input) {
  for (final command in input.commands) {
    final lease = f.text.singleWhere(
      (t) =>
          t.nativeInputIdentity == command.nativeInputIdentity &&
          (t is! ForumBodyTextBandChildLease ||
              t.childIndex == command.bandChildIndex),
    );
    canvas.save();
    try {
      canvas.translate(command.offset.dx, command.offset.dy);
      canvas.scale(command.fitScale);
      lease.layout.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final band in [false, true]) {
    test('composition records one exact positioned scene band=$band', () async {
      final f = _Fixture(band: band, entries: 3);
      final before = (
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.hitCount,
        f.cache.activeLeases,
      );
      final combined = _finish(
        ForumBodyTextPictureInputComposition(
          inputs: [
            (input: f.a, offset: const Offset(3, 7)),
            (input: f.b, offset: const Offset(17, 23)),
          ],
          ensureOwner: () {},
        ),
      );
      expect((
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.hitCount,
        f.cache.activeLeases,
      ), before);
      expect(
        combined.estimatedBytes,
        lessThan(f.a.estimatedBytes + f.b.estimatedBytes),
      );
      expect(combined.commands[0].offset, const Offset(5, 10));
      expect(combined.commands[2].offset, const Offset(22, 78));
      expect(combined.commands[0].fitScale, .63);
      expect(combined.commands[2].fitScale, .75);
      expect(combined.commands[0].bandChildIndex, band ? 0 : null);
      final scene = ForumBodyTextPicturePreparation(
        cache: f.cache,
        input: combined,
        text: f.text,
        ensureOwner: () {},
      );
      addTearDown(scene.close);
      while (!scene.isReady) {
        scene.advance(maxParts: 1);
      }
      final lease = scene.takeLease();
      addTearDown(lease.release);
      expect(f.cache.pictureBuildCount, before.$2 + 1);
      expect(f.cache.entryCount, band ? 2 : 3);
      final pictures = <ui.Picture>[];
      addTearDown(() {
        for (final p in pictures) {
          p.dispose();
        }
      });
      Future<List<int>> pixels(void Function(Canvas) draw, int dpr) async {
        final recorder = ui.PictureRecorder();
        draw(Canvas(recorder)..scale(dpr.toDouble()));
        final picture = recorder.endRecording();
        pictures.add(picture);
        final image = await picture.toImage(180 * dpr, 140 * dpr);
        try {
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      for (final dpr in [1, 3]) {
        final expected = await pixels((canvas) {
          canvas.save();
          canvas.translate(3, 7);
          _draw(canvas, f, f.a);
          canvas.restore();
          canvas.save();
          canvas.translate(17, 23);
          _draw(canvas, f, f.b);
          canvas.restore();
        }, dpr);
        expect(
          await pixels((canvas) => lease.paint(canvas, Offset.zero), dpr),
          expected,
        );
      }
      lease.release();
    });
  }
  for (final count in [1, 127, 128, 129, 255, 256, 257, 8192, 32768]) {
    test(
      'direct and composed identity agree across hash chunks count=$count',
      () {
        final f = _Fixture(), command = f.a.commands.first;
        final direct = ForumBodyTextPictureInput(
          commands: List.filled(count, command),
          maxCommands: count,
        );
        final sources = <ForumBodyPositionedTextPictureInput>[];
        for (var index = 0; index < count; index += 127) {
          sources.add((
            input: ForumBodyTextPictureInput(
              commands: List.filled(math.min(127, count - index), command),
            ),
            offset: Offset.zero,
          ));
        }
        final job = ForumBodyTextPictureInputComposition(
          inputs: sources,
          ensureOwner: () {},
          maxCommands: count,
        );
        var parts = 0;
        while (!job.isReady) {
          parts += job.advance(maxParts: 1);
        }
        expect(parts, greaterThan(count));
        final combined = job.takeInput();
        expect(combined, direct);
        expect(combined.hashCode, direct.hashCode);
        expect(combined.estimatedInputBytes, direct.estimatedInputBytes);
        expect(() => combined.commands.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'source lists are independent after construction and pure inputs outlive native owners',
    () {
      final f = _Fixture(), commands = f.a.commands.toList();
      final input = ForumBodyTextPictureInput(commands: commands);
      commands.clear();
      f.cache.close();
      final result = _finish(
        ForumBodyTextPictureInputComposition(
          inputs: [(input: input, offset: const Offset(1, 2))],
          ensureOwner: () {},
        ),
      );
      expect(result.commands, hasLength(2));
      expect(result.commands.first.offset, const Offset(3, 5));
    },
  );
  test(
    'source/command/coordinate limits retire partial composition without touching caller resources',
    () {
      final f = _Fixture(), before = f.cache.activeLeases;
      final sources = [
        (input: f.a, offset: Offset.zero),
        (input: f.b, offset: Offset.zero),
      ];
      for (final job in [
        ForumBodyTextPictureInputComposition(
          inputs: sources,
          ensureOwner: () {},
          maxInputs: 1,
        ),
        ForumBodyTextPictureInputComposition(
          inputs: sources,
          ensureOwner: () {},
          maxCommands: 3,
        ),
        ForumBodyTextPictureInputComposition(
          inputs: [(input: f.a, offset: const Offset(32768, 0))],
          ensureOwner: () {},
        ),
        ForumBodyTextPictureInputComposition(
          inputs: const [],
          ensureOwner: () {},
        ),
      ]) {
        expect(() => _finish(job), throwsArgumentError);
        expect(job.takeInput, throwsStateError);
      }
      expect(
        () => ForumBodyTextPictureInput(
          commands: f.a.commands,
          maxCommands: 32769,
        ),
        throwsArgumentError,
      );
      expect(f.cache.activeLeases, before);
    },
  );
  test('iterator and ready-owner retirement prevent publication', () {
    final f = _Fixture();
    late ForumBodyTextPictureInputComposition job;
    Iterable<ForumBodyPositionedTextPictureInput> sources() sync* {
      yield (input: f.a, offset: Offset.zero);
      job.close();
      yield (input: f.b, offset: Offset.zero);
    }

    job = ForumBodyTextPictureInputComposition(
      inputs: sources(),
      ensureOwner: () {},
    );
    expect(() => _finish(job), throwsStateError);
    var active = true;
    final ready = ForumBodyTextPictureInputComposition(
      inputs: [(input: f.a, offset: Offset.zero)],
      ensureOwner: () {
        if (!active) throw StateError('Retired');
      },
    );
    while (!ready.isReady) {
      ready.advance(maxParts: 1);
    }
    active = false;
    expect(ready.takeInput, throwsStateError);
    expect(f.cache.activeLeases, 2);
  });
  test('reentry and cancellation discard only the composed metadata', () {
    final f = _Fixture();
    var armed = false;
    late ForumBodyTextPictureInputComposition job;
    job = ForumBodyTextPictureInputComposition(
      inputs: [(input: f.a, offset: Offset.zero)],
      ensureOwner: () {
        if (armed) job.advance(maxParts: 1);
      },
    );
    armed = true;
    expect(() => job.advance(maxParts: 1), throwsStateError);
    expect(f.cache.activeLeases, 2);
    final cancelled = ForumBodyTextPictureInputComposition(
      inputs: [(input: f.a, offset: Offset.zero)],
      ensureOwner: () {},
    );
    cancelled.advance(maxParts: 3);
    cancelled.close();
    cancelled.close();
    expect(cancelled.takeInput, throwsStateError);
    expect(f.cache.activeLeases, 2);
  });
}
