import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(37.25, 35.5),
    alignment: ui.PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 29.75,
  ),
];

ForumBodyParagraphCache _cache({int entries = 32}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 25,
  );
  addTearDown(c.close);
  return c;
}

ForumBodyInlineParagraphLease _parent(
  ForumBodyParagraphCache c, {
  double height = 1.35,
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  String suffix = ' Y Y Y Y Y Y',
  double? pitch,
  ForumBodyParagraphPaintLayer? layer,
}) {
  final input = mixedInlineInput(
        prefix: 'P P P P P P ',
        suffix: suffix,
        direction: direction.name,
        paragraphStyle: 'line-height:$height',
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            color: Color(0xff112233),
            backgroundColor: Color(0x55336699),
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            shadows: [
              Shadow(
                offset: Offset(1.25, -2.75),
                color: Color(0xaa993322),
                blurRadius: 1.5,
              ),
            ],
          ),
          fontRevision: 'natural-window',
          linkColor: const Color(0xff0000ff),
        ),
      ).content,
      content = layer == null
          ? input
          : ForumBodyInlinePaintInput(input).foreground;
  final p = c.acquireInline(
    content: content,
    width: 83.25,
    dimensions: _dimensions,
    textScaler: scaler,
    rowIsolationPitch: pitch,
  );
  addTearDown(p.release);
  return p;
}

ForumBodyInlinePaintRowView _window(
  ForumBodyInlineParagraphLease p,
  int start,
  int end, {
  void Function()? owner,
}) => ForumBodyInlinePaintRowView.naturalWindow(
  parent: p,
  startLine: start,
  endLine: end,
  ensureOwner: owner ?? () {},
);

ForumBodyTextPicturePreparation _work(
  ForumBodyParagraphCache c,
  List<ForumBodyInlinePaintRowView> rows, {
  void Function()? owner,
}) => ForumBodyTextPicturePreparation.cooperative(
  cache: c,
  input: ForumBodyTextPictureInput(
    commands: [
      for (final (i, row) in rows.indexed)
        ForumBodyTextPictureCommand.fromInlineRow(
          row,
          Offset(2.25 + i * 110.25, 3.75),
        ).translated(const Offset(11.3, 7.7)),
    ],
  ),
  text: const [],
  inlineRows: rows,
  ensureOwner: owner ?? () {},
);

void _bind(ForumBodyTextPicturePreparation w) {
  for (var n = 0; !w.dependenciesReady; n++) {
    expect(n, lessThan(10000));
    final step = w.advance(maxParts: 1, cachedOnly: true);
    expect(step.partsPrepared, 1);
    expect(step.picturesRecorded, 0);
  }
}

ForumBodyTextPictureLease _finish(
  ForumBodyTextPicturePreparation w,
  ForumBodyParagraphCache c, {
  bool warm = false,
}) {
  try {
    for (var n = 0; !w.isReady; n++) {
      expect(n, lessThan(10000));
      final before = (c.layoutBuildCount, c.pictureBuildCount),
          step = w.advance(maxParts: 1, cachedOnly: warm);
      expect(step.partsPrepared, 1);
      expect(step.waitingForLayoutBudget || w.cacheMiss, isFalse);
      expect(c.layoutBuildCount, before.$1);
      expect(c.pictureBuildCount - before.$2, warm ? 0 : lessThanOrEqualTo(1));
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
    final image = await p.toImage((470 * dpr).ceil(), (300 * dpr).ceil());
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final height in [.4, 1.35]) {
      for (final scaler in [TextScaler.noScaling, const _Curve()]) {
        for (final dpr in [1.0, 1.25, 3.0]) {
          test('natural window preserves exact fragment paint '
              '$direction/$height/$scaler/$dpr', () async {
            final c = _cache(),
                p = _parent(
                  c,
                  direction: direction,
                  height: height,
                  scaler: scaler,
                ),
                native = p.layout,
                last = p.layout.lines.length - 1,
                ranges = [(0, 1), (1, last), (last, last + 1), (0, last + 1)],
                rows = [for (final (a, b) in ranges) _window(p, a, b)],
                input = _work(c, rows);
            expect(last, greaterThan(1));
            final reference = await _pixels((cv) {
              for (final (i, range) in ranges.indexed) {
                cv.save();
                cv.translate(11.3, 7.7);
                p.layout
                    .fragment(range.$1, range.$2)
                    .paintParent(cv, Offset(2.25 + i * 110.25, 3.75));
                cv.restore();
              }
            }, dpr);
            expect(reference.any((x) => x != 0), isTrue);
            while (!input.cacheMiss) {
              final step = input.advance(maxParts: 1, cachedOnly: true);
              expect(step.picturesRecorded, 0);
            }
            expect(input.dependenciesReady, isTrue);
            // All four actual fragment selectors borrow ONE private alias.
            expect(input.nativeLeases, hasLength(1));
            expect(identical(input.nativeLeases.single, p), isFalse);
            final warmWork = _work(c, rows);
            _bind(warmWork);
            p.release();
            final picture = _finish(input, c),
                warm = _finish(warmWork, c, warm: true);
            addTearDown(picture.release);
            addTearDown(warm.release);
            expect(c.pictureBuildCount, 1);
            c.clearUnpinned();
            expect(c.entryCount, 1);
            expect(c.activeLeases, 2);
            expect(native.isDisposed, isTrue);
            expect(
              await _pixels((cv) => picture.paint(cv, Offset.zero), dpr),
              orderedEquals(reference),
            );
            expect(
              await _pixels((cv) => warm.paint(cv, Offset.zero), dpr),
              orderedEquals(reference),
            );
            picture.release();
            warm.release();
            c.clearUnpinned();
            expect(c.entryCount, 0);
            expect(c.activeLeases, 0);
          });
        }
      }
    }
  }

  test('terminal empty window never exposes previous glyphs', () async {
    final c = _cache(),
        p = _parent(c, suffix: 'Y<br>', height: .25),
        last = p.layout.lines.length - 1,
        row = _window(p, last, last + 1);
    expect(row.selector.isEmpty, isTrue);
    final w = _work(c, [row]);
    _bind(w);
    p.release();
    final scene = _finish(w, c);
    addTearDown(scene.release);
    expect(
      (await _pixels(
        (cv) => scene.paint(cv, Offset.zero),
        1.25,
      )).every((x) => x == 0),
      isTrue,
    );
  });

  test('selectors keep actual natural windows distinct and source-free', () {
    final c = _cache(),
        p = _parent(c),
        a = _window(p, 0, 1),
        b = _window(p, 0, 2);
    expect(a.selector, _window(p, 0, 1).selector);
    expect(a.selector, isNot(b.selector));
    expect(a.selector.isNaturalWindow, isTrue);
    expect(a.selector.windowEndLine, 1);
    expect(a.selector.matchesInput(p.nativeInputIdentity), isTrue);
    final workA = _work(c, [a]), workB = _work(c, [b]);
    expect(workA.input, isNot(workB.input));
    workA.close();
    workB.close();
    expect(() => _window(p, -1, 1), throwsRangeError);
    expect(() => _window(p, 0, 0), throwsRangeError);
    expect(() => _window(p, 0, p.layout.lines.length + 1), throwsRangeError);
    expect(
      () => ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand(
            nativeInputIdentity: p.nativeInputIdentity,
            offset: Offset.zero,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('isolated and paint-layer parents cannot create natural windows', () {
    final c = _cache(),
        isolated = _parent(c, pitch: 400),
        phase = _parent(c, layer: ForumBodyParagraphPaintLayer.foreground);
    expect(
      () => _window(isolated, 0, 1),
      throwsA(isA<ForumBodyParagraphLayoutException>()),
    );
    expect(
      () => _window(phase, 0, 1),
      throwsA(isA<ForumBodyParagraphLayoutException>()),
    );
  });

  test(
    'equal native keys do not authorize another current source or owner',
    () {
      final c = _cache(),
          other = _cache(),
          p = _parent(c),
          equalSource = _parent(c),
          foreign = _parent(other),
          row = _window(p, 0, 1);
      expect(p.nativeInputIdentity, equalSource.nativeInputIdentity);
      expect(identical(p.content, equalSource.content), isFalse);
      expect(
        () => row.bindAlias(parent: equalSource, ensureOwner: () {}),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      expect(
        () => row.bindAlias(parent: foreign, ensureOwner: () {}),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      final work = _work(c, [_window(foreign, 0, 1)]);
      expect(() => _bind(work), throwsStateError);
      work.close();
      expect(c.activeLeases, 2);
      expect(other.activeLeases, 1);
    },
  );

  test('retirement during rebind releases only its private parent alias', () {
    final c = _cache(), p = _parent(c);
    ForumBodyTextPicturePreparation? work;
    var retire = false;
    var calls = 0, leasesAtRetirement = 0;
    final row = _window(
      p,
      0,
      1,
      owner: () {
        if (retire && ++calls == 2) {
          leasesAtRetirement = c.activeLeases;
          work!.close();
        }
      },
    );
    work = _work(c, [row]);
    retire = true;
    expect(() => _bind(work!), throwsStateError);
    expect(leasesAtRetirement, 2);
    expect(c.activeLeases, 1);
    expect(p.isActive, isTrue);
    expect(c.pictureBuildCount, 0);
  });

  test('cancel at every dependency step leaves the caller parent active', () {
    final c = _cache(),
        p = _parent(c),
        rows = [_window(p, 0, 1), _window(p, 1, 2)];
    final measured = _work(c, rows);
    var count = 0;
    while (!measured.dependenciesReady) {
      measured.advance(maxParts: 1, cachedOnly: true);
      count++;
    }
    measured.close();
    for (var cut = 0; cut <= count; cut++) {
      final work = _work(c, rows);
      for (var i = 0; i < cut; i++) {
        work.advance(maxParts: 1, cachedOnly: true);
      }
      work.close();
      expect(c.activeLeases, 1);
      expect(p.isActive, isTrue);
      expect(c.pictureBuildCount, 0);
    }
  });
}

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 15 ? 1.35 : 1.13);
  @override
  double get textScaleFactor => 1.13;
}
