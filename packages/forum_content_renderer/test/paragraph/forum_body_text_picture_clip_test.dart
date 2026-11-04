import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

ForumBodyParagraphCache _cache() {
  final c = ForumBodyParagraphCache(maxEntries: 32, maxEstimatedBytes: 1 << 25);
  addTearDown(c.close);
  return c;
}

ForumBodyTextPicturePreparation _work(
  ForumBodyParagraphCache c,
  ForumBodyTextPictureInput input, {
  Iterable<ForumBodyTextLease> text = const [],
  Iterable<ForumBodyTextPictureLease> pictures = const [],
  Iterable<ForumBodyInlinePaintRowView> rows = const [],
}) => ForumBodyTextPicturePreparation.cooperative(
  cache: c,
  input: input,
  text: text,
  pictures: pictures,
  inlineRows: rows,
  ensureOwner: () {},
);

void _bind(ForumBodyTextPicturePreparation w) {
  for (var n = 0; !w.dependenciesReady; n++) {
    expect(n, lessThan(10000));
    expect(w.advance(maxParts: 1, cachedOnly: true).picturesRecorded, 0);
  }
}

ForumBodyTextPictureLease _finish(
  ForumBodyTextPicturePreparation w, {
  bool warm = false,
}) {
  try {
    for (var n = 0; !w.isReady; n++) {
      expect(n, lessThan(10000));
      final step = w.advance(maxParts: 1, cachedOnly: warm);
      expect(step.partsPrepared, 1);
      expect(step.picturesRecorded, warm ? 0 : lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget || w.cacheMiss, isFalse);
    }
    return w.takeLease();
  } finally {
    w.close();
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, double dpr) async {
  final r = ui.PictureRecorder();
  paint(Canvas(r)..scale(dpr));
  final p = r.endRecording();
  try {
    final image = await p.toImage((370 * dpr).ceil(), (160 * dpr).ceil());
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    p.dispose();
  }
}

ForumBodyTextPictureCommand _fill() => ForumBodyTextPictureCommand.fillRect(
  rect: const Rect.fromLTWH(0, 0, 120, 120),
  color: const Color(0x9944aa88),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const inner = Offset(7.3, 11.9),
      innerClip = Rect.fromLTRB(1.25, 3.75, 73.5, 82.25),
      outerClip = Rect.fromLTRB(10.5, 15.5, 60.25, 70.75);
  for (final translatedClip in [false, true]) {
    for (final fit in [1.0, .63]) {
      for (final dpr in [1.0, 1.25, 3.0]) {
        test('ordered hard scopes with actual text/window/picture '
            '$translatedClip/$fit/$dpr', () async {
          final c = _cache(),
              source = mixedInlineInput(
                prefix: 'PPP',
                suffix: 'YYYY',
                paragraphStyle: 'line-height:.4',
              ),
              text = c.acquire(content: source.contexts.first, width: 120),
              parent = c.acquireInline(
                content: source.content,
                width: 65.25,
                dimensions: const [
                  PlaceholderDimensions(
                    size: Size(40, 30),
                    alignment: ui.PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    baselineOffset: 26,
                  ),
                ],
              ),
              native = parent.layout,
              fragment = native.fragment(0, native.lines.length),
              row = ForumBodyInlinePaintRowView.naturalWindow(
                parent: parent,
                startLine: 0,
                endLine: native.lines.length,
                ensureOwner: () {},
              ),
              child = _finish(
                _work(c, ForumBodyTextPictureInput(commands: [_fill()])),
              );
          final originals = [
            ForumBodyTextPictureCommand.fromText(
              text,
              const Offset(2.75, 4.25),
              fitScale: fit,
            ),
            ForumBodyTextPictureCommand.fromInlineRow(
              row,
              const Offset(.125, 20.75),
            ),
            ForumBodyTextPictureCommand.fromPicture(
              child,
              const Offset(7.5, 11.75),
              fitScale: fit,
            ),
          ];
          ForumBodyTextPictureCommand wrap(
            ForumBodyTextPictureCommand command,
            int i,
          ) {
            final clipped = command.clipped(innerClip),
                scoped = translatedClip
                    ? clipped.clipped(outerClip).translated(inner)
                    : clipped.translated(inner).clipped(outerClip);
            return scoped.translated(Offset(25.125 + i * 100, 9.375));
          }

          final input = ForumBodyTextPictureInput(
            commands: [
              for (final (i, command) in originals.indexed) wrap(command, i),
              // A previous command's scope must never affect its following sibling.
              ForumBodyTextPictureCommand.fillRect(
                rect: const Rect.fromLTWH(330, 10, 15, 15),
                color: const Color(0xff123456),
              ),
            ],
          );
          final expected = await _pixels((cv) {
            for (var i = 0; i < 3; i++) {
              cv.save();
              cv.translate(25.125 + i * 100, 9.375);
              if (translatedClip) cv.translate(inner.dx, inner.dy);
              cv.clipRect(outerClip, doAntiAlias: false);
              if (!translatedClip) cv.translate(inner.dx, inner.dy);
              cv.clipRect(innerClip, doAntiAlias: false);
              final offset = originals[i].offset;
              if (i != 1 && fit != 1) {
                cv.translate(offset.dx, offset.dy);
                cv.scale(fit);
              }
              final local = i != 1 && fit != 1 ? Offset.zero : offset;
              if (i == 0) text.layout.paint(cv, local);
              if (i == 1) fragment.paintParent(cv, local);
              if (i == 2) child.paint(cv, local);
              cv.restore();
            }
            cv.drawRect(
              const Rect.fromLTWH(330, 10, 15, 15),
              Paint()..color = const Color(0xff123456),
            );
          }, dpr);
          final w = _work(
                c,
                input,
                text: [text],
                pictures: [child],
                rows: [row],
              ),
              warmJob = _work(
                c,
                input,
                text: [text],
                pictures: [child],
                rows: [row],
              );
          _bind(w);
          _bind(warmJob);
          expect(w.nativeLeases, hasLength(3));
          final builds = c.layoutBuildCount;
          text.release();
          parent.release();
          child.release();
          final scene = _finish(w), warm = _finish(warmJob, warm: true);
          addTearDown(scene.release);
          addTearDown(warm.release);
          c.clearUnpinned();
          expect(c.layoutBuildCount, builds);
          expect(c.pictureBuildCount, 2);
          expect(c.entryCount, 1);
          expect(c.activeLeases, 2);
          expect(native.isDisposed, isTrue);
          expect(
            await _pixels((cv) => scene.paint(cv, Offset.zero), dpr),
            orderedEquals(expected),
          );
          expect(
            await _pixels((cv) => warm.paint(cv, Offset.zero), dpr),
            orderedEquals(expected),
          );
          scene.release();
          warm.release();
          c.clearUnpinned();
          expect(c.activeLeases, 0);
          expect(c.entryCount, 0);
        });
      }
    }
  }

  test(
    'clip/translation order, empty scope and explicit metadata are preserved',
    () {
      final a = _fill().clipped(innerClip).translated(inner),
          b = _fill().translated(inner).clipped(innerClip);
      expect(a, isNot(b));
      expect({a, b}, hasLength(2));
      expect(a.sceneOffset, b.sceneOffset);
      expect(a.translations, [inner]);
      expect(a.clips, [innerClip]);
      expect(a.clipDepth, 1);
      expect(a.translationDepth, 1);
      final base = ForumBodyTextPictureInput(commands: [_fill()]),
          clipped = ForumBodyTextPictureInput(
            commands: [_fill().clipped(innerClip)],
          );
      expect(
        clipped.estimatedInputBytes - base.estimatedInputBytes,
        ForumBodyTextPictureCommand.clipInputEstimatedBytes,
      );
      expect(
        clipped.estimatedPictureBytes - base.estimatedPictureBytes,
        ForumBodyTextPictureCommand.clipPictureEstimatedBytes,
      );
      expect(() => a.clipped(Rect.zero), returnsNormally);
      expect(
        () => _fill().clipped(const Rect.fromLTRB(4, 0, 3, 1)),
        throwsArgumentError,
      );
      expect(
        () => _fill().clipped(const Rect.fromLTRB(0, 4, 1, 3)),
        throwsArgumentError,
      );
      for (final value in [
        double.nan,
        double.infinity,
        -double.infinity,
        32769.0,
        -32769.0,
      ]) {
        expect(
          () => _fill().clipped(Rect.fromLTRB(value, 0, 1, 2)),
          throwsArgumentError,
        );
        expect(
          () => _fill().clipped(Rect.fromLTRB(0, value, 1, 2)),
          throwsArgumentError,
        );
        expect(
          () => _fill().clipped(Rect.fromLTRB(0, 0, value, 2)),
          throwsArgumentError,
        );
        expect(
          () => _fill().clipped(Rect.fromLTRB(0, 0, 1, value)),
          throwsArgumentError,
        );
      }
    },
  );

  test('independent clip/translation bounds stay finite when interleaved', () {
    var command = _fill();
    for (var i = 0; i < ForumBodyTextPictureCommand.maximumClipDepth; i++) {
      command = command.clipped(innerClip);
      if (i < ForumBodyTextPictureCommand.maximumTranslationDepth) {
        command = command.translated(const Offset(1, 1));
      }
    }
    expect(command.clipDepth, ForumBodyTextPictureCommand.maximumClipDepth);
    expect(
      command.translationDepth,
      ForumBodyTextPictureCommand.maximumTranslationDepth,
    );
    expect(() => command.clipped(innerClip), throwsArgumentError);
    expect(() => command.translated(inner), throwsArgumentError);
    expect(
      () => ForumBodyTextPictureInput(commands: [command]),
      returnsNormally,
    );
  });

  test(
    'pure composition keeps ordered clips without native dependencies',
    () async {
      final c = _cache(),
          command = _fill().clipped(innerClip).translated(inner),
          source = ForumBodyTextPictureInput(commands: [command]),
          work = ForumBodyTextPictureInputComposition(
            inputs: [(input: source, offset: const Offset(20, 30))],
            ensureOwner: () {},
          );
      try {
        while (!work.isReady) {
          expect(work.advance(maxParts: 1), 1);
        }
        final combined = work.takeInput();
        expect(
          combined.commands.single,
          command.translated(const Offset(20, 30)),
        );
        final w = _work(c, combined);
        _bind(w);
        expect(w.nativeLeases, isEmpty);
        final scene = _finish(w);
        addTearDown(scene.release);
        final expected = await _pixels((cv) {
          cv.translate(20, 30);
          cv.translate(inner.dx, inner.dy);
          cv.clipRect(innerClip, doAntiAlias: false);
          cv.drawRect(
            const Rect.fromLTWH(0, 0, 120, 120),
            Paint()..color = const Color(0x9944aa88),
          );
        }, 1.25);
        expect(
          await _pixels((cv) => scene.paint(cv, Offset.zero), 1.25),
          orderedEquals(expected),
        );
        expect(c.layoutBuildCount, 0);
      } finally {
        work.close();
      }
    },
  );

  test('empty hard clip affects only its own command', () async {
    final c = _cache(),
        input = ForumBodyTextPictureInput(
          commands: [
            _fill().clipped(Rect.zero),
            ForumBodyTextPictureCommand.fillRect(
              rect: const Rect.fromLTWH(130, 10, 10, 10),
              color: const Color(0xff123456),
            ),
          ],
        ),
        scene = _finish(_work(c, input));
    addTearDown(scene.release);
    final expected = await _pixels(
      (cv) => cv.drawRect(
        const Rect.fromLTWH(130, 10, 10, 10),
        Paint()..color = const Color(0xff123456),
      ),
      3,
    );
    expect(
      await _pixels((cv) => scene.paint(cv, Offset.zero), 3),
      orderedEquals(expected),
    );
  });
}
