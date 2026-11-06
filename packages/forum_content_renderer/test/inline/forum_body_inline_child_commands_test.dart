import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache() {
  final c = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(c.close);
  return c;
}

ForumBodyInlineEmphasisChildView _children(
  ForumBodyParagraphCache c,
  String child, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  bool authoredRuby = false,
}) {
  final source = measureMixedEmphasisAllocatedSource(
        MixedEmphasisParentFixture(
          child,
          direction: direction,
          width: 140,
          prefix: 'P P P P ',
          suffix: ' Q Q Q',
          authoredRuby: authoredRuby,
        ),
        c,
        scaler: scaler,
      ),
      work = ForumBodyInlineEmphasisChildPreparation(
        allocation: source.allocation,
        natural: source.natural,
        cache: c,
        expectedTextScaler: scaler,
        ensureOwner: () {},
        additionalOwnedLeases: () => [source.source],
      );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    final children = work.takeView();
    addTearDown(children.close);
    source.natural.release();
    source.source.release();
    return children;
  } finally {
    work.close();
  }
}

final class _Commands {
  final text = <Object, ForumBodyTextLease>{};
  final pictures = <Object, ForumBodyTextPictureLease>{};
  final rows = <ForumBodyInlinePaintRowSelector, ForumBodyInlinePaintRowView>{};
  final commands = <ForumBodyTextPictureCommand>[];
  int steps = 0, emptySteps = 0;
  ForumBodyTextPictureInputComposition compose(
    Iterable<ForumBodyInlinePaintCommand?> source, {
    void Function()? owner,
    int maxSteps = 131072,
  }) => ForumBodyTextPictureInputComposition.commandSteps(
    steps: source.map((step) {
      steps++;
      if (step == null) {
        emptySteps++;
        return null;
      }
      final row = step.row, resource = step.resource;
      if (row != null) {
        rows[row.selector] = row;
      } else if (resource is ForumBodyTextLease) {
        text[(
              resource.nativeInputIdentity,
              resource is ForumBodyTextBandChildLease
                  ? resource.childIndex
                  : null,
            )] =
            resource;
      } else if (resource is ForumBodyTextPictureLease) {
        pictures[resource.nativeInputIdentity] = resource;
      } else {
        expect(resource, isNull);
        expect(step.command.isFill, isTrue);
      }
      commands.add(step.command);
      return step.command;
    }),
    maxSteps: maxSteps,
    ensureOwner: owner ?? () {},
  );
  ForumBodyTextPicturePreparation record(
    ForumBodyParagraphCache c,
    ForumBodyTextPictureInput input,
  ) => ForumBodyTextPicturePreparation.cooperative(
    cache: c,
    input: input,
    text: text.values,
    pictures: pictures.values,
    inlineRows: rows.values,
    ensureOwner: () {},
  );
}

ForumBodyTextPictureInput _collect(
  ForumBodyParagraphCache c,
  _Commands captured,
  Iterable<ForumBodyInlinePaintCommand?> steps,
) {
  final before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases),
      work = captured.compose(steps);
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(100000));
      final count = captured.steps;
      expect(work.advance(maxParts: 1), 1);
      expect(captured.steps - count, inInclusiveRange(0, 1));
      expect((c.layoutBuildCount, c.pictureBuildCount, c.activeLeases), before);
    }
    final input = work.takeInput();
    expect(
      input,
      ForumBodyTextPictureInput(commands: captured.commands, maxCommands: 8192),
    );
    expect(
      input.estimatedBytes,
      ForumBodyTextPictureInput(
        commands: captured.commands,
        maxCommands: 8192,
      ).estimatedBytes,
    );
    return input;
  } finally {
    work.close();
  }
}

void _bind(ForumBodyTextPicturePreparation work) {
  for (var n = 0; !work.dependenciesReady; n++) {
    expect(n, lessThan(100000));
    expect(work.advance(maxParts: 1, cachedOnly: true).picturesRecorded, 0);
  }
}

ForumBodyTextPictureLease _finish(
  ForumBodyTextPicturePreparation work, {
  bool warm = false,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(100000));
      final step = work.advance(maxParts: 1, cachedOnly: warm);
      expect(step.partsPrepared, 1);
      expect(step.picturesRecorded, warm ? 0 : lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget || work.cacheMiss, isFalse);
    }
    return work.takeLease();
  } finally {
    work.close();
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, double dpr) async {
  final r = ui.PictureRecorder();
  paint(Canvas(r)..scale(dpr));
  final p = r.endRecording();
  try {
    final image = await p.toImage((280 * dpr).ceil(), (240 * dpr).ceil());
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

String _background(String child) => child.startsWith('<ruby style="')
    ? child.replaceFirst(
        'style="',
        'style="background-color:rgba(30,80,140,.37);',
      )
    : child.replaceFirst(
        '<ruby>',
        '<ruby style="background-color:rgba(30,80,140,.37)">',
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  final samples = [
    ...mixedEmphasisChildren,
    '<ruby style="font-size:12px"><rb><ruby>A<rt>x</rt></ruby></rb><rt>z</rt></ruby>',
  ];
  for (var i = 0; i < samples.length; i++) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        test(
          'actual child command order/pixels/resources $i/$direction/$scaler',
          () async {
            final c = _cache(),
                view = _children(
                  c,
                  _background(samples[i]),
                  direction: direction,
                  scaler: scaler,
                  authoredRuby: i == 4,
                ),
                captured = _Commands();
            const origin = Offset(7.3, 11.9);
            final input = _collect(c, captured, view.paintCommands(origin));
            expect(captured.emptySteps, greaterThan(0));
            expect(captured.commands.first.isFill, isTrue);
            expect(captured.text, isNotEmpty);
            if (i == 4) expect(captured.rows, isNotEmpty);
            if (i == 1 || i == 2 || i == 6) {
              expect(captured.pictures, isEmpty);
            }
            final references = [
                  for (final dpr in [1.0, 1.25, 3.0])
                    await _pixels((cv) {
                      view.paintContainerBackgrounds(cv, origin);
                      for (final atom in view.atomIndices) {
                        view.paintAtom(cv, origin, atom);
                      }
                    }, dpr),
                ],
                cold = captured.record(c, input),
                warm = captured.record(c, input),
                builds = (c.layoutBuildCount, c.pictureBuildCount);
            while (!cold.cacheMiss) {
              expect(
                cold.advance(maxParts: 1, cachedOnly: true).picturesRecorded,
                0,
              );
            }
            _bind(warm);
            view.close();
            final scene = _finish(cold), reused = _finish(warm, warm: true);
            addTearDown(scene.release);
            addTearDown(reused.release);
            expect(c.layoutBuildCount, builds.$1);
            expect(c.pictureBuildCount, builds.$2 + 1);
            c.clearUnpinned();
            expect(c.entryCount, 1);
            expect(c.activeLeases, 2);
            for (var j = 0; j < 3; j++) {
              final dpr = [1.0, 1.25, 3.0][j];
              expect(
                await _pixels((cv) => scene.paint(cv, Offset.zero), dpr),
                orderedEquals(references[j]),
              );
            }
            scene.release();
            reused.release();
            c.clearUnpinned();
            expect(c.entryCount, 0);
            expect(c.activeLeases, 0);
          },
        );
      }
    }
  }

  test(
    'cancel every input step keeps all borrowed native ownership untouched',
    () {
      final c = _cache(),
          view = _children(c, _background(samples[4]), authoredRuby: true),
          captured = _Commands();
      _collect(c, captured, view.paintCommands(Offset.zero));
      final before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases);
      for (var cut = 0; cut <= captured.steps + 2; cut++) {
        final collector = _Commands(),
            work = collector.compose(view.paintCommands(Offset.zero));
        for (var n = 0; n < cut && !work.isReady; n++) {
          work.advance(maxParts: 1);
        }
        work.close();
        expect((
          c.layoutBuildCount,
          c.pictureBuildCount,
          c.activeLeases,
        ), before);
        expect(view.isActive, isTrue);
      }
    },
  );

  test(
    'source retirement during traversal or before dependency adoption fails',
    () {
      final c = _cache(),
          view = _children(c, samples[4], authoredRuby: true),
          captured = _Commands(),
          work = captured.compose(view.paintCommands(Offset.zero));
      work.advance(maxParts: 4);
      view.close();
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsStateError);
      work.close();
      expect(c.activeLeases, 0);
      final next = _children(c, samples[1]),
          nextCaptured = _Commands(),
          input = _collect(c, nextCaptured, next.paintCommands(Offset.zero));
      next.close();
      final record = nextCaptured.record(c, input);
      expect(() => _bind(record), throwsStateError);
      record.close();
      expect(c.activeLeases, 0);
    },
  );

  test(
    'command-step composition limits structural work and guards producer callbacks',
    () {
      final command = ForumBodyTextPictureCommand.fillRect(
        rect: Rect.zero,
        color: const Color(0x00000000),
      );
      Iterable<ForumBodyTextPictureCommand?> steps() sync* {
        yield command;
        while (true) {
          yield null;
        }
      }

      final work = ForumBodyTextPictureInputComposition.commandSteps(
        steps: steps(),
        ensureOwner: () {},
        maxSteps: 8,
      );
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsArgumentError);
      expect(() => work.takeInput(), throwsStateError);
      final one = ForumBodyTextPictureInputComposition.commandSteps(
        steps: [command],
        ensureOwner: () {},
        maxSteps: 1,
      );
      while (!one.isReady) {
        one.advance(maxParts: 1);
      }
      expect(one.takeInput().commands, [command]);
      one.close();
      expect(
        () => ForumBodyTextPictureInputComposition.commandSteps(
          steps: [command],
          ensureOwner: () {},
          maxSteps: 0,
        ),
        throwsArgumentError,
      );
    },
  );

  for (final point in ['iterator', 'move', 'current']) {
    test(
      'retirement from command producer $point cannot publish late input',
      () {
        late ForumBodyTextPictureInputComposition work;
        var calls = 0;
        final source = _TrapSteps(point, () {
          calls++;
          work.close();
        });
        work = ForumBodyTextPictureInputComposition.commandSteps(
          steps: source,
          ensureOwner: () {},
        );
        expect(() {
          while (!work.isReady) {
            work.advance(maxParts: 1);
          }
        }, throwsStateError);
        expect(calls, 1);
        expect(() => work.takeInput(), throwsStateError);
        work.close();
      },
    );
  }

  test('command limits and ink-free output fail without a partial input', () {
    final command = ForumBodyTextPictureCommand.fillRect(
      rect: Rect.zero,
      color: const Color(0x00000000),
    );
    for (final steps in <List<ForumBodyTextPictureCommand?>>[
      [command, null, command],
      [null, null],
      [],
    ]) {
      final work = ForumBodyTextPictureInputComposition.commandSteps(
        steps: steps,
        ensureOwner: () {},
        maxCommands: 1,
      );
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsArgumentError);
      expect(() => work.takeInput(), throwsStateError);
      work.close();
    }
  });
}

final class _TrapSteps extends Iterable<ForumBodyTextPictureCommand?> {
  _TrapSteps(this.point, this.retire);
  final String point;
  final void Function() retire;
  @override
  Iterator<ForumBodyTextPictureCommand?> get iterator {
    if (point == 'iterator') retire();
    return _TrapIterator(point, retire);
  }
}

final class _TrapIterator implements Iterator<ForumBodyTextPictureCommand?> {
  _TrapIterator(this.point, this.retire);
  final String point;
  final void Function() retire;
  @override
  bool moveNext() {
    if (point == 'move') retire();
    return true;
  }

  @override
  ForumBodyTextPictureCommand? get current {
    if (point == 'current') retire();
    return ForumBodyTextPictureCommand.fillRect(
      rect: Rect.zero,
      color: const Color(0x00000000),
    );
  }
}
