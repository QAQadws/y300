import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/text_picture_fixture.dart';

final class _Observed<T> extends IterableBase<T> {
  _Observed(this.values, {this.onOpen, this.onMove, this.onRead});
  final List<T> values;
  final void Function()? onOpen, onMove, onRead;
  int opened = 0, moved = 0, read = 0;
  @override
  Iterator<T> get iterator {
    opened++;
    onOpen?.call();
    return _ObservedIterator(this);
  }
}

final class _ObservedIterator<T> implements Iterator<T> {
  _ObservedIterator(this.source);
  final _Observed<T> source;
  int index = -1;
  @override
  bool moveNext() {
    source.moved++;
    source.onMove?.call();
    return ++index < source.values.length;
  }

  @override
  T get current {
    source.read++;
    source.onRead?.call();
    return source.values[index];
  }
}

ForumBodyTextPicturePreparation _open(
  TextPictureFixture f, {
  ForumBodyTextPictureInput? input,
  Iterable<ForumBodyTextLease>? text,
  Iterable<ForumBodyEmphasisMarkLease> marks = const [],
  Iterable<ForumBodyParagraphRowView> rows = const [],
  void Function()? owner,
  Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
}) => ForumBodyTextPicturePreparation.cooperative(
  cache: f.cache,
  input: input ?? f.input,
  text: text ?? f.text,
  marks: marks,
  paragraphRows: rows,
  ensureOwner: owner ?? () {},
  additionalOwnedLeases: prefix,
);

void _bind(ForumBodyTextPicturePreparation work) {
  for (var n = 0; !work.dependenciesReady; n++) {
    expect(n, lessThan(20000));
    final step = work.advance(maxParts: 1, cachedOnly: true);
    expect(step.partsPrepared, 1);
    expect(step.picturesRecorded, 0);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(work.cacheMiss, isFalse);
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, int dpr) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(120 * dpr, 80 * dpr);
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

({ForumBodyParagraphLease parent, List<ForumBodyParagraphRowView> rows}) _rows(
  TextPictureFixture f, {
  void Function()? owner,
}) {
  final doc = const ForumBodyParser().parse(
    html: '<p>ABCD</p>',
    sourceId: 'cooperative-scene-rows',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
  );
  final parent = f.cache.acquire(
    content: content,
    width: 40,
    rowIsolationPitch: 80,
  );
  addTearDown(parent.release);
  f.cache.prepareTextPaint(parent);
  final rows = <ForumBodyParagraphRowView>[];
  for (var start = 0; start < parent.layout.lineCount;) {
    final work = ForumBodyParagraphRowPreparation(
      parent: parent,
      startLine: start,
      ensureOwner: () {},
    );
    late ForumBodyParagraphRowMetrics metrics;
    try {
      while (!work.isReady) {
        work.advance(maxParts: 1);
      }
      metrics = work.takeMetrics();
    } finally {
      work.close();
    }
    rows.add(
      ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: owner ?? () {},
      ),
    );
    start = metrics.selector.endLine;
  }
  return (parent: parent, rows: rows);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'constructor borrows without traversing; each command/resource is deferred to its own part',
    () {
      final f = TextPictureFixture(), source = _Observed(f.text);
      const count = 256;
      final input = ForumBodyTextPictureInput(
        commands: [
          for (var i = 0; i < count; i++)
            ForumBodyTextPictureCommand.fromText(
              f.text[i % 2],
              Offset((i % 8).toDouble(), (i ~/ 8).toDouble()),
            ),
        ],
      );
      final before = (
        f.cache.layoutBuildCount,
        f.cache.pictureBuildCount,
        f.cache.activeLeases,
      );
      var prefixes = 0;
      final work = _open(
        f,
        input: input,
        text: source,
        prefix: () {
          prefixes++;
          return const [];
        },
      );
      try {
        expect(work.dependenciesReady, isFalse);
        expect(work.nativeLeases, isEmpty);
        expect((source.opened, source.moved, source.read), (0, 0, 0));
        expect((
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        ), before);
        for (var n = 0; n < count; n++) {
          expect(work.advance(maxParts: 1).partsPrepared, 1);
          expect(source.opened, 0);
          expect(f.cache.activeLeases, before.$3);
        }
        var parts = count;
        while (!work.dependenciesReady) {
          final previous = (
            source.opened,
            source.moved,
            source.read,
            f.cache.activeLeases,
          );
          expect(work.advance(maxParts: 1).partsPrepared, 1);
          expect(source.opened - previous.$1, inInclusiveRange(0, 1));
          expect(source.moved - previous.$2, inInclusiveRange(0, 1));
          expect(source.read - previous.$3, inInclusiveRange(0, 1));
          expect(f.cache.activeLeases - previous.$4, inInclusiveRange(0, 1));
          expect(prefixes, 0);
          parts++;
        }
        expect(parts, lessThan(count + 20));
        expect(work.nativeLeases, hasLength(2));
        expect(
          (f.cache.layoutBuildCount, f.cache.pictureBuildCount),
          (before.$1, before.$2),
        );
        for (final text in f.text) {
          text.release();
        }
        final scene = f.finish(work);
        scene.release();
        expect(f.cache.activeLeases, 0);
      } finally {
        work.close();
      }
    },
  );
  for (final band in [false, true]) {
    for (final dpr in [1, 3]) {
      test(
        'cooperative native pixels match direct glyph/marker drawing band=$band DPR$dpr',
        () async {
          final f = TextPictureFixture(band: band);
          final mark = f.cache.acquireEmphasisMark(
            input: ForumBodyEmphasisMarkInput(
              style: f.text[0].content.style.withTextEmphasis(
                const ForumBodyTextEmphasis(
                  shape: ForumBodyEmphasisShape.circle,
                ),
              ),
              fontRevision: f.text[0].content.fontRevision,
              styleRevision: f.text[0].content.styleRevision,
            ),
          );
          addTearDown(mark.release);
          final input = ForumBodyTextPictureInput(
            commands: [
              ...f.input.commands,
              ForumBodyTextPictureCommand.fromEmphasisMark(
                mark,
                const Offset(50.3, 6.7),
                fitScale: .63,
              ).translated(const Offset(1.2, 2.4)),
            ],
          );
          final scene = f.finish(_open(f, input: input, marks: [mark]));
          try {
            final actual = await _pixels(
              (c) => scene.paint(c, Offset.zero),
              dpr,
            );
            final expected = await _pixels((c) {
              f.text[0].layout.paint(c, const Offset(5, 25));
              f.text[1].layout.paint(c, const Offset(15, 5));
              f.text[0].layout.paint(c, const Offset(65, 25));
              c.save();
              c.translate(1.2, 2.4);
              c.translate(50.3, 6.7);
              c.scale(.63, .63);
              mark.layout.paint(c, Offset.zero);
              c.restore();
            }, dpr);
            expect(actual, expected);
            expect(actual.any((value) => value > 0), isTrue);
          } finally {
            scene.release();
          }
        },
      );
    }
  }
  test(
    'row selectors share one actual parent alias after cooperative binding',
    () {
      final f = TextPictureFixture(), data = _rows(f);
      expect(data.rows, hasLength(2));
      final input = ForumBodyTextPictureInput(
        commands: [
          for (final row in data.rows)
            ForumBodyTextPictureCommand.fromParagraphRow(
              row,
              Offset(0, row.selector.originY),
            ),
        ],
      );
      final before = f.cache.activeLeases;
      final work = _open(f, input: input, text: const [], rows: data.rows);
      _bind(work);
      expect(f.cache.activeLeases, before + 1);
      expect(work.nativeLeases, hasLength(1));
      data.parent.release();
      final scene = f.finish(work);
      scene.release();
      expect(f.cache.activeLeases, 2);
    },
  );
  test(
    'cold cached-only miss preserves aliases; warm composition records nothing',
    () {
      final f = TextPictureFixture(),
          work = _open(f),
          before = f.cache.pictureBuildCount;
      for (var n = 0; !work.cacheMiss; n++) {
        expect(n, lessThan(1000));
        work.advance(maxParts: 1, cachedOnly: true);
      }
      expect(work.dependenciesReady, isTrue);
      expect(work.nativeLeases, hasLength(2));
      expect(f.cache.pictureBuildCount, before);
      final value = f.finish(work);
      value.release();
      final built = f.cache.pictureBuildCount;
      final warm = _open(f);
      final cached = f.finish(warm, cachedOnly: true);
      cached.release();
      expect(f.cache.pictureBuildCount, built);
      expect(warm.dependenciesReady, isFalse);
    },
  );
  test(
    'releasing an unconsumed borrowed dependency fails without stealing other sources',
    () {
      final f = TextPictureFixture(), work = _open(f);
      f.text[1].release();
      expect(() => f.finish(work), throwsStateError);
      expect(f.text[0].isActive, isTrue);
      expect(f.cache.activeLeases, 1);
      work.close();
    },
  );
  test(
    'foreign, unrequested, missing and excess inputs fail during advance and release private aliases',
    () {
      final f = TextPictureFixture(), foreign = TextPictureFixture();
      for (final (sources, failure)
          in <(Iterable<ForumBodyTextLease>, Matcher)>[
            (foreign.text, throwsStateError),
            ([f.text[1]], throwsArgumentError),
            (const [], throwsArgumentError),
            (_Observed(List.filled(10000, f.text[0])), throwsArgumentError),
          ]) {
        final input = ForumBodyTextPictureInput(
          commands: [f.input.commands.first],
        );
        final work = _open(f, input: input, text: sources);
        expect(work.nativeLeases, isEmpty);
        expect(() => f.finish(work), failure);
        work.close();
        expect(f.cache.activeLeases, 2);
        expect(foreign.cache.activeLeases, 2);
        if (sources case final _Observed<ForumBodyTextLease> observed) {
          expect(observed.moved, 2);
          expect(observed.read, 2);
        }
      }
    },
  );
  for (final event in ['iterator', 'moveNext', 'current']) {
    test('retirement in caller $event leaves no late dependency alias', () {
      final f = TextPictureFixture();
      ForumBodyTextPicturePreparation? work;
      void retire() => work!.close();
      final sources = _Observed(
        f.text,
        onOpen: event == 'iterator' ? retire : null,
        onMove: event == 'moveNext' ? retire : null,
        onRead: event == 'current' ? retire : null,
      );
      work = _open(f, text: sources);
      expect(() => f.finish(work!), throwsStateError);
      expect(f.cache.activeLeases, 2);
      expect(f.cache.pictureBuildCount, 0);
    });
  }
  test(
    'caught reentry from a source iterator preserves the outer transaction',
    () {
      final f = TextPictureFixture();
      ForumBodyTextPicturePreparation? work;
      final sources = _Observed(
        f.text,
        onRead: () {
          expect(work!.advance, throwsStateError);
          expect(work.takeLease, throwsStateError);
        },
      );
      work = _open(f, text: sources);
      final scene = f.finish(work);
      scene.release();
      expect(f.cache.activeLeases, 2);
    },
  );
  test(
    'row owner retirement during key capture and alias adoption cleans partial work',
    () {
      for (final duringAlias in [false, true]) {
        final f = TextPictureFixture();
        ForumBodyTextPicturePreparation? work;
        var armed = false;
        final before = f.cache.activeLeases;
        final data = _rows(
          f,
          owner: () {
            if (armed && !duringAlias) work!.close();
          },
        );
        final input = ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromParagraphRow(
              data.rows.first,
              Offset.zero,
            ),
          ],
        );
        work = _open(
          f,
          input: input,
          text: const [],
          rows: [data.rows.first],
          owner: () {
            if (armed && duringAlias && f.cache.activeLeases > before + 1) {
              work!.close();
            }
          },
        );
        armed = true;
        expect(() => f.finish(work!), throwsStateError);
        expect(data.parent.isActive, isTrue);
        expect(f.cache.activeLeases, before + 1);
      }
    },
  );
  test(
    'all cooperative work boundaries retire without releasing caller handles',
    () {
      final f = TextPictureFixture(), counter = _open(f);
      var parts = 0;
      while (!counter.isReady) {
        parts += counter.advance(maxParts: 1).partsPrepared;
      }
      counter.close();
      for (var stop = 0; stop <= parts; stop++) {
        f.cache.clearUnpinned();
        var active = true;
        final work = _open(
          f,
          owner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takeLease, throwsStateError);
        work.close();
        expect(work.dependenciesReady, isFalse);
        expect(f.cache.activeLeases, 2);
      }
    },
  );
  for (final owned in [false, true]) {
    test(
      'external pin waits while owned impossible prefix fails owned=$owned',
      () {
        final f = TextPictureFixture(entries: 3);
        final source = f.text[0].content;
        final pin = f.cache.acquire(
          content: ForumBodyParagraphContent.anonymousInline(
            identity: source.identity,
            fontRevision: source.fontRevision,
            styleRevision: source.styleRevision,
            style: source.style,
          ),
          width: 100,
        );
        addTearDown(pin.release);
        final work = _open(f, prefix: owned ? () => [pin] : null);
        try {
          if (owned) {
            expect(
              () => f.finish(work),
              throwsA(
                isA<ForumBodyParagraphBudgetException>().having(
                  (e) => e.failure,
                  'failure',
                  ForumBodyParagraphBudgetFailure.content,
                ),
              ),
            );
            expect(pin.isActive, isTrue);
            expect(f.cache.pictureBuildCount, 0);
          } else {
            for (var n = 0; ; n++) {
              expect(n, lessThan(1000));
              if (work.advance(maxParts: 1).waitingForLayoutBudget) break;
            }
            final aliases = work.nativeLeases.toList();
            expect(work.advance().partsPrepared, 0);
            expect(work.nativeLeases, aliases);
            pin.release();
            f.finish(work).release();
          }
        } finally {
          work.close();
        }
      },
    );
  }
  test(
    'native recording retirement cannot publish late cooperative scenes',
    () {
      final f = TextPictureFixture(), work = _open(f);
      final oldCreate = ui.Picture.onCreate, oldDispose = ui.Picture.onDispose;
      var created = 0, disposed = 0;
      ui.Picture.onCreate = (_) {
        created++;
        work.close();
      };
      ui.Picture.onDispose = (_) {
        disposed++;
      };
      try {
        expect(() => f.finish(work), throwsStateError);
        expect(created, 1);
        expect(disposed, 1);
        expect(f.cache.pictureBuildCount, 0);
        expect(f.cache.activeLeases, 2);
      } finally {
        ui.Picture.onCreate = oldCreate;
        ui.Picture.onDispose = oldDispose;
        work.close();
      }
    },
  );
}
