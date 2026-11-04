import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/text_picture_fixture.dart';

typedef _Fixture = TextPictureFixture;

Future<List<int>> _pixels(void Function(Canvas) draw, int ratio) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(120 * ratio, 80 * ratio);
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

String _heavyText() => [
  for (var i = 0; i < 200; i++)
    '<span style="color:${i.isEven ? '#123456' : '#654321'}">A</span>',
].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fitted band commands keep child selection and sibling transforms',
    () async {
      final f = _Fixture(band: true);
      final input = ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand.fromText(
            f.text[0],
            const Offset(5, 25),
            fitScale: .63,
          ),
          ForumBodyTextPictureCommand.fromText(
            f.text[1],
            const Offset(15, 5),
            fitScale: .37,
          ),
          ForumBodyTextPictureCommand.fromText(f.text[0], const Offset(65, 25)),
        ],
      );
      final job = ForumBodyTextPicturePreparation(
        cache: f.cache,
        input: input,
        text: f.text,
        ensureOwner: () {},
      );
      final controls = [
        for (final text in f.text)
          TextPainter(
            text: text.content.textSpan,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: double.infinity),
      ];
      final scene = f.finish(job);
      try {
        for (final text in f.text) {
          text.release();
        }
        f.cache.clearUnpinned();
        expect(f.cache.entryCount, 1);
        final expected = await _pixels((canvas) {
          void fitted(TextPainter text, Offset offset, double scale) {
            canvas.save();
            canvas.translate(offset.dx, offset.dy);
            canvas.scale(scale, scale);
            text.paint(canvas, Offset.zero);
            canvas.restore();
          }

          fitted(controls[0], const Offset(5, 25), .63);
          fitted(controls[1], const Offset(15, 5), .37);
          controls[0].paint(canvas, const Offset(65, 25));
        }, 3);
        expect(
          await _pixels((canvas) => scene.paint(canvas, Offset.zero), 3),
          expected,
        );
      } finally {
        scene.release();
        for (final text in controls) {
          text.dispose();
        }
      }
    },
  );
  for (final band in [false, true]) {
    for (final ratio in [1, 3]) {
      test(
        'actual native scene matches independent pixels DPR$ratio band=$band',
        () async {
          final f = _Fixture(band: band);
          final job = f.open();
          final builds = f.cache.layoutBuildCount,
              pictures = f.cache.pictureBuildCount;
          final value = f.finish(job);
          job.close();
          final a = TextPainter(
            text: const TextSpan(
              text: 'AB',
              style: TextStyle(
                fontFamily: 'Ahem',
                fontSize: 20,
                height: 1,
                color: Color(0xffff0000),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final b = TextPainter(
            text: const TextSpan(
              text: 'xy',
              style: TextStyle(
                fontFamily: 'Ahem',
                fontSize: 10,
                height: 1,
                color: Color(0xff0000ff),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          try {
            final expected = await _pixels((c) {
              a.paint(c, const Offset(5, 25));
              b.paint(c, const Offset(15, 5));
              a.paint(c, const Offset(65, 25));
            }, ratio);
            expect(
              await _pixels((c) => value.paint(c, Offset.zero), ratio),
              expected,
            );
            expect(f.cache.layoutBuildCount, builds);
            expect(f.cache.pictureBuildCount, pictures + 1);
            expect(f.cache.preparedPictureCount, band ? 3 : 1);
            // The scene owns its display list. Source paragraphs can be released
            // and evicted without retaining a painter outside the owner's budget.
            for (final text in f.text) {
              text.release();
            }
            f.cache.clearUnpinned();
            expect(f.cache.entryCount, 1);
            expect(f.cache.activeLeases, 1);
            expect(
              await _pixels((c) => value.paint(c, Offset.zero), ratio),
              expected,
            );
            expect(f.cache.layoutBuildCount, builds);
            expect(f.cache.pictureBuildCount, pictures + 1);
          } finally {
            a.dispose();
            b.dispose();
            value.release();
          }
          f.cache.clearUnpinned();
          expect(f.cache.estimatedRetainedBytes, 0);
          expect(f.cache.preparedPictureCount, 0);
        },
      );
    }
  }

  test(
    'cold cached-only miss resumes the same job and warm scene does no native work',
    () {
      final f = _Fixture();
      final job = f.open();
      while (!job.cacheMiss) {
        job.advance(maxParts: 1, cachedOnly: true);
      }
      expect(f.cache.pictureBuildCount, 0);
      final originalBuilds = f.cache.layoutBuildCount;
      final first = f.finish(job);
      expect(f.cache.activeLeases, 3);
      first.release();
      final warm = f.open();
      final second = f.finish(warm, cachedOnly: true);
      expect(f.cache.layoutBuildCount, originalBuilds);
      expect(f.cache.pictureBuildCount, 1);
      expect(second.input, f.input);
      second.release();
      job.close();
      warm.close();
      expect(f.cache.activeLeases, 2);
    },
  );

  test(
    'private aliases preserve prepared source resources after caller release',
    () {
      final f = _Fixture();
      final job = f.open();
      expect(f.cache.activeLeases, 4);
      for (final text in f.text) {
        text.release();
      }
      f.cache.clearUnpinned();
      expect(f.cache.entryCount, 2);
      final picture = f.finish(job);
      expect(f.cache.activeLeases, 1);
      picture.release();
      job.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'actual foreign pins wait without recording or changing the held prefix',
    () {
      final f = _Fixture(entries: 3);
      final extra = f.cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: f.text[0].content.identity,
          fontRevision: f.text[0].content.fontRevision,
          styleRevision: f.text[0].content.styleRevision,
          style: f.text[0].content.style,
        ),
        width: 100,
      );
      final job = f.open();
      var waiting = false;
      for (var i = 0; !waiting && i < 20; i++) {
        waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      final held = job.nativeLeases.toList();
      expect(held, hasLength(2));
      expect(job.advance().partsPrepared, 0);
      expect(job.nativeLeases, orderedEquals(held));
      expect(f.cache.pictureBuildCount, 0);
      extra.release();
      final picture = f.finish(job);
      expect(f.text.every((lease) => lease.isActive), isTrue);
      picture.release();
      job.close();
      expect(f.cache.activeLeases, 2);
    },
  );

  test(
    'own full entry footprint fails before recording instead of waiting',
    () {
      final f = _Fixture(entries: 2);
      final job = f.open();
      expect(
        () => f.finish(job),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 2);
      expect(f.text.every((lease) => lease.isActive), isTrue);
      job.close();
    },
  );

  test('page prefix is included before recording and is never released', () {
    final f = _Fixture(entries: 3);
    final prefix = f.cache.acquire(
      content: ForumBodyParagraphContent.anonymousInline(
        identity: f.text[0].content.identity,
        fontRevision: f.text[0].content.fontRevision,
        styleRevision: f.text[0].content.styleRevision,
        style: f.text[0].content.style,
      ),
      width: 100,
    );
    addTearDown(prefix.release);
    final job = f.open(additionalOwnedLeases: () => [prefix]);
    expect(
      () => f.finish(job),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect(prefix.isActive, isTrue);
    expect(f.cache.activeLeases, 3);
    expect(f.cache.pictureBuildCount, 0);
  });

  test('prefix aliases deduplicate with scene dependencies', () {
    final f = _Fixture(entries: 3);
    final picture = f.finish(
      f.open(additionalOwnedLeases: () => [f.text[0], f.text[0], f.text[1]]),
    );
    expect(f.cache.entryCount, 3);
    expect(f.cache.activeLeases, 3);
    picture.release();
    expect(f.text.every((value) => value.isActive), isTrue);
  });

  test('external pressure preserves the page prefix and resumes its scene', () {
    final f = _Fixture(entries: 4);
    final empty = ForumBodyParagraphContent.anonymousInline(
      identity: f.text[0].content.identity,
      fontRevision: f.text[0].content.fontRevision,
      styleRevision: f.text[0].content.styleRevision,
      style: f.text[0].content.style,
    );
    final prefix = f.cache.acquire(content: empty, width: 100);
    final external = f.cache.acquire(
      content: empty,
      width: 100,
      textScaler: const TextScaler.linear(1.1),
    );
    addTearDown(prefix.release);
    addTearDown(external.release);
    final job = f.open(additionalOwnedLeases: () => [prefix]);
    var waiting = false;
    for (var i = 0; !waiting && i < 100; i++) {
      waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
    }
    expect(waiting, isTrue);
    expect(f.cache.pictureBuildCount, 0);
    final held = job.nativeLeases.toList();
    expect(job.advance().partsPrepared, 0);
    external.release();
    final picture = f.finish(job);
    expect(held.every((value) => !value.isActive), isTrue);
    expect(prefix.isActive, isTrue);
    expect(f.text.every((value) => value.isActive), isTrue);
    expect(f.cache.activeLeases, 4);
    picture.release();
  });

  test('late picture growth counts own prefix rather than waiting for it', () {
    final source = _Fixture(first: _heavyText());
    source.finish(source.open()).release();
    final f = _Fixture(
      first: _heavyText(),
      bytes: source.cache.estimatedRetainedBytes + 512,
    );
    final prefix = f.cache.acquire(
      content: ForumBodyParagraphContent.anonymousInline(
        identity: f.text[0].content.identity,
        fontRevision: f.text[0].content.fontRevision,
        styleRevision: f.text[0].content.styleRevision,
        style: f.text[0].content.style,
      ),
      width: 100,
    );
    addTearDown(prefix.release);
    final job = f.open(additionalOwnedLeases: () => [prefix]);
    var created = 0, disposed = 0;
    final oldCreate = ui.Picture.onCreate, oldDispose = ui.Picture.onDispose;
    ui.Picture.onCreate = (_) {
      created++;
    };
    ui.Picture.onDispose = (_) {
      disposed++;
    };
    try {
      expect(
        () => f.finish(job),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
    } finally {
      ui.Picture.onCreate = oldCreate;
      ui.Picture.onDispose = oldDispose;
      job.close();
    }
    expect(created, 1);
    expect(disposed, 1);
    expect(f.cache.pictureBuildCount, 0);
    expect(prefix.isActive, isTrue);
    expect(f.cache.activeLeases, 3);
  });

  test(
    'prefix inspection yields after one handle and cancels only aliases',
    () {
      final f = _Fixture();
      var inspected = 0;
      Iterable<ForumBodyNativeParagraphLease> prefix() sync* {
        for (var i = 0; i < 50; i++) {
          inspected++;
          yield f.text[0];
        }
      }

      final job = f.open(additionalOwnedLeases: prefix);
      job.advance(maxParts: 1);
      expect(inspected, 0);
      for (var i = 1; i <= 3; i++) {
        final step = job.advance(maxParts: 1);
        expect(step.partsPrepared, 1);
        expect(inspected, i);
        expect(f.cache.pictureBuildCount, 0);
      }
      job.close();
      expect(f.cache.activeLeases, 2);
    },
  );

  for (final lazy in [false, true]) {
    test('prefix callback retirement cannot publish a scene (lazy=$lazy)', () {
      final f = _Fixture();
      late ForumBodyTextPicturePreparation job;
      Iterable<ForumBodyNativeParagraphLease> lazyPrefix() sync* {
        job.close();
        yield f.text[0];
      }

      job = f.open(
        additionalOwnedLeases: () {
          if (lazy) return lazyPrefix();
          job.close();
          return f.text;
        },
      );
      expect(() => f.finish(job), throwsStateError);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 2);
    });
  }

  for (final retired in [false, true]) {
    test('foreign or retired prefix is not ownership (retired=$retired)', () {
      final f = _Fixture(), other = _Fixture();
      final prefix = retired
          ? f.cache.acquire(
              content: ForumBodyParagraphContent.anonymousInline(
                identity: f.text[0].content.identity,
                fontRevision: f.text[0].content.fontRevision,
                styleRevision: f.text[0].content.styleRevision,
                style: f.text[0].content.style,
              ),
              width: 100,
            )
          : other.text[0];
      if (retired) prefix.release();
      final job = f.open(additionalOwnedLeases: () => [prefix]);
      expect(() => f.finish(job), throwsStateError);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 2);
      expect(other.cache.activeLeases, 2);
    });
  }

  test(
    'own complete byte footprint fails without recording and leaves source active',
    () {
      final source = _Fixture();
      final f = _Fixture(
        bytes:
            source.cache.estimatedRetainedBytes +
            source.input.estimatedBytes -
            1,
      );
      final job = f.open();
      expect(
        () => f.finish(job),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(f.cache.activeLeases, 2);
      expect(f.cache.pictureBuildCount, 0);
    },
  );

  test(
    'scene budget snapshots deduplicate its native input and remain pure',
    () {
      final f = _Fixture();
      final probe = f.cache.createBudgetProbe(captureInputEstimates: true);
      probe.includeTextPicture(f.input);
      probe.includeTextPicture(f.input);
      final costs = probe.snapshotNativeEstimates();
      expect(costs, hasLength(1));
      expect(costs.single.estimatedBytes, f.input.estimatedBytes);
      probe.close();
      final value = f.finish(f.open());
      expect(costs.single.identity, value.nativeInputIdentity);
      value.release();
      f.cache.close();
      expect(costs.single.estimatedBytes, greaterThan(0));
    },
  );

  test(
    'measured display-list growth is admitted before publication and rejected tickets are released',
    () {
      final heavy = _heavyText();
      final source = _Fixture(first: heavy);
      final fontBytes = source.cache.estimatedRetainedBytes;
      final before = source.cache.pictureBuildCount;
      final previous = ui.Picture.onCreate;
      var actual = 0;
      ui.Picture.onCreate = (picture) {
        actual = picture.approximateBytesUsed;
      };
      late ForumBodyTextPictureLease picture;
      try {
        picture = source.finish(source.open());
      } finally {
        ui.Picture.onCreate = previous;
      }
      try {
        expect(actual, greaterThan(source.input.estimatedPictureBytes));
        expect(
          picture.nativeLayoutEstimatedBytes,
          source.input.estimatedInputBytes + actual,
        );
        expect(
          source.cache.estimatedRetainedBytes,
          fontBytes + source.input.estimatedInputBytes + actual,
        );
        expect(source.cache.pictureBuildCount, before + 1);
      } finally {
        picture.release();
      }
      final f = _Fixture(
        first: heavy,
        bytes: fontBytes + source.input.estimatedBytes,
      );
      final job = f.open();
      final previousCreate = ui.Picture.onCreate,
          previousDispose = ui.Picture.onDispose;
      var created = 0, disposed = 0;
      ui.Picture.onCreate = (_) {
        created++;
      };
      ui.Picture.onDispose = (_) {
        disposed++;
      };
      try {
        expect(
          () => f.finish(job),
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
      } finally {
        ui.Picture.onCreate = previousCreate;
        ui.Picture.onDispose = previousDispose;
        job.close();
      }
      expect(created, 1);
      expect(disposed, 1);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 2);
      expect(f.cache.estimatedRetainedBytes, fontBytes);
    },
  );

  test(
    'late display-list pressure waits on the same job and re-records only after capacity changes',
    () {
      final heavy = _heavyText();
      final source = _Fixture(first: heavy);
      final picture = source.finish(source.open());
      final sceneBytes = picture.nativeLayoutEstimatedBytes;
      picture.release();
      final f = _Fixture(
        first: heavy,
        bytes: source.cache.estimatedRetainedBytes + 512,
      );
      final extra = f.cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: f.text[0].content.identity,
          fontRevision: f.text[0].content.fontRevision,
          styleRevision: f.text[0].content.styleRevision,
          style: f.text[0].content.style,
        ),
        width: 100,
      );
      final job = f.open();
      var recorded = 0, waiting = false;
      for (var i = 0; !waiting && i < 100; i++) {
        final step = job.advance(maxParts: 1);
        recorded += step.picturesRecorded;
        waiting = step.waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      expect(recorded, 1);
      expect(f.cache.pictureBuildCount, 0);
      expect(job.advance().partsPrepared, 0);
      expect(job.nativeLeases, hasLength(2));
      extra.release();
      final current = f.finish(job);
      expect(current.nativeLayoutEstimatedBytes, sceneBytes);
      expect(f.cache.pictureBuildCount, 1);
      current.release();
      job.close();
      expect(f.cache.activeLeases, 2);
    },
  );

  for (final cancelAt in [0, 1, 3, 4, 5, 6, 7, 8]) {
    test('cancelled recording releases its aliases at unit$cancelAt', () {
      final f = _Fixture();
      final job = f.open();
      for (var i = 0; i < cancelAt && !job.isReady; i++) {
        job.advance(maxParts: 1);
      }
      job.close();
      job.close();
      expect(f.cache.activeLeases, 2);
      expect(f.text.every((lease) => lease.isActive), isTrue);
      expect(() => job.advance(), throwsStateError);
      expect(() => job.takeLease(), throwsStateError);
    });
  }

  for (final retireCache in [false, true]) {
    test(
      'native picture creation retirement cannot publish late resources cache=$retireCache',
      () {
        final f = _Fixture();
        final job = f.open();
        final previousCreate = ui.Picture.onCreate,
            previousDispose = ui.Picture.onDispose;
        var created = 0, disposed = 0;
        ui.Picture.onCreate = (picture) {
          created++;
          if (retireCache) {
            f.cache.close();
          } else {
            job.close();
          }
        };
        ui.Picture.onDispose = (_) {
          disposed++;
        };
        try {
          expect(() => f.finish(job), throwsStateError);
        } finally {
          ui.Picture.onCreate = previousCreate;
          ui.Picture.onDispose = previousDispose;
          job.close();
        }
        expect(created, 1);
        expect(disposed, 1);
        expect(f.cache.activeLeases, retireCache ? 0 : 2);
        expect(f.cache.pictureBuildCount, 0);
      },
    );
  }

  test(
    'take reentrancy is rejected while owner cancellation remains permitted',
    () {
      final f = _Fixture();
      late ForumBodyTextPicturePreparation job;
      var taking = false, rejected = false;
      job = f.open(
        owner: () {
          if (taking) {
            expect(() => job.advance(), throwsStateError);
            rejected = true;
          }
        },
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      taking = true;
      final value = job.takeLease();
      expect(rejected, isTrue);
      value.release();
      job.close();
      expect(f.cache.activeLeases, 2);
    },
  );

  test(
    'cached-only calls during a partial recording do not advance native work',
    () {
      final f = _Fixture();
      final job = f.open();
      for (var i = 0; i < 5; i++) {
        job.advance(maxParts: 1);
      }
      final held = job.nativeLeases.toList();
      final step = job.advance(maxParts: 1, cachedOnly: true);
      expect(job.cacheMiss, isTrue);
      expect(step.partsPrepared, 0);
      expect(step.picturesRecorded, 0);
      expect(job.nativeLeases, orderedEquals(held));
      final value = f.finish(job);
      expect(f.cache.pictureBuildCount, 1);
      value.release();
      job.close();
    },
  );

  test(
    'owner retirement after a cached lookup releases the acquired alias',
    () {
      final f = _Fixture();
      f.finish(f.open()).release();
      final hits = f.cache.hitCount;
      late ForumBodyTextPicturePreparation job;
      job = f.open(
        owner: () {
          if (f.cache.hitCount > hits) job.close();
        },
      );
      expect(() => f.finish(job), throwsStateError);
      expect(f.cache.activeLeases, 2);
      expect(f.cache.pictureBuildCount, 1);
      job.close();
    },
  );

  test('eviction retirement cannot allocate a late recorder', () {
    final f = _Fixture(entries: 3);
    f.finish(f.open()).release();
    final different = ForumBodyTextPictureInput(
      commands: [
        for (final command in f.input.commands)
          ForumBodyTextPictureCommand(
            nativeInputIdentity: command.nativeInputIdentity,
            bandChildIndex: command.bandChildIndex,
            offset: command.offset + const Offset(1, 0),
          ),
      ],
    );
    final job = ForumBodyTextPicturePreparation(
      cache: f.cache,
      input: different,
      text: f.text,
      ensureOwner: () {},
    );
    final oldCreate = ui.Picture.onCreate, oldDispose = ui.Picture.onDispose;
    var created = 0, disposed = 0;
    ui.Picture.onCreate = (_) {
      created++;
    };
    ui.Picture.onDispose = (_) {
      disposed++;
      job.close();
    };
    try {
      expect(() => f.finish(job), throwsStateError);
    } finally {
      ui.Picture.onCreate = oldCreate;
      ui.Picture.onDispose = oldDispose;
      job.close();
    }
    expect(created, 0);
    expect(disposed, 1);
    expect(f.cache.activeLeases, 2);
    expect(f.cache.entryCount, 2);
  });

  test(
    'retirement during final picture admission cannot refill the cache late',
    () {
      final f = _Fixture(entries: 3);
      final job = f.open();
      for (var i = 0; i < 4; i++) {
        job.advance(maxParts: 1);
      }
      final different = ForumBodyTextPictureInput(
        commands: [
          for (final command in f.input.commands)
            ForumBodyTextPictureCommand(
              nativeInputIdentity: command.nativeInputIdentity,
              bandChildIndex: command.bandChildIndex,
              offset: command.offset + const Offset(1, 0),
            ),
        ],
      );
      final other = ForumBodyTextPicturePreparation(
        cache: f.cache,
        input: different,
        text: f.text,
        ensureOwner: () {},
      );
      f.finish(other).release();
      other.close();
      final oldDispose = ui.Picture.onDispose;
      var disposed = 0;
      ui.Picture.onDispose = (_) {
        disposed++;
        job.close();
      };
      try {
        expect(() => f.finish(job), throwsStateError);
      } finally {
        ui.Picture.onDispose = oldDispose;
        job.close();
      }
      expect(disposed, 2);
      expect(f.cache.pictureBuildCount, 1);
      expect(f.cache.entryCount, 2);
      expect(f.cache.activeLeases, 2);
      expect(f.cache.tryAcquireTextPicture(f.input), isNull);
    },
  );

  test(
    'source views, command order and positions are immutable parts of the key',
    () {
      final f = _Fixture(band: true);
      expect(f.text[0].nativeInputIdentity, f.text[1].nativeInputIdentity);
      final commands = [
        ForumBodyTextPictureCommand.fromText(f.text[0], Offset.zero),
      ];
      final first = ForumBodyTextPictureInput(commands: commands);
      commands[0] = ForumBodyTextPictureCommand.fromText(
        f.text[1],
        Offset.zero,
      );
      final second = ForumBodyTextPictureInput(commands: commands);
      expect(first, isNot(second));
      expect(first.commands.single.bandChildIndex, 0);
      expect(second.commands.single.bandChildIndex, 1);
      expect(() => first.commands.clear(), throwsUnsupportedError);
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: f.text[0].nativeInputIdentity,
              offset: Offset.zero,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: Object(),
              offset: Offset.zero,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromText(
              f.text[0],
              const Offset(double.nan, 0),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: f.cache,
          input: first,
          text: [f.text[1]],
          ensureOwner: () {},
        ),
        throwsArgumentError,
      );
      expect(f.cache.activeLeases, 2);
    },
  );

  test(
    'same pure keys cannot authorize foreign text or missing nested pictures',
    () {
      final f = _Fixture(), other = _Fixture();
      expect(f.input, other.input);
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: f.cache,
          input: f.input,
          text: other.text,
          ensureOwner: () {},
        ),
        throwsStateError,
      );
      final value = f.finish(f.open());
      final nested = ForumBodyTextPictureInput(
        commands: [ForumBodyTextPictureCommand.fromPicture(value, Offset.zero)],
      );
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: f.cache,
          input: nested,
          text: const [],
          ensureOwner: () {},
        ),
        throwsArgumentError,
      );
      value.release();
      f.cache.close();
      final recorder = ui.PictureRecorder();
      try {
        expect(
          () => value.paint(Canvas(recorder), Offset.zero),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
      }
      expect(f.cache.estimatedRetainedBytes, 0);
    },
  );
}
