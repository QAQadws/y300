import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

const _layers = [
  ForumBodyParagraphPaintLayer.background,
  ForumBodyParagraphPaintLayer.foreground,
  ForumBodyParagraphPaintLayer.decoration,
];

ForumBodyParagraphCache _cache({int entries = 512}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(c.close);
  return c;
}

MixedEmphasisAllocatedSource _source(
  ForumBodyParagraphCache c, {
  String? child,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  bool logical = false,
  String prefix = 'P P P P P P P P ',
  String suffix = ' Q Q Q Q',
  String style = 'text-emphasis:circle;line-height:.4',
  double width = 180,
}) => measureMixedEmphasisAllocatedSource(
  MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren.first,
    direction: direction,
    width: width,
    prefix: prefix,
    suffix: suffix,
    parentStyle: style,
    readerTextStyle: TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      color: const Color(0xff123456),
      backgroundColor: logical ? const Color(0x44112233) : null,
      decoration: logical ? TextDecoration.underline : null,
      decorationStyle: TextDecorationStyle.wavy,
      shadows: const [
        Shadow(
          color: Color(0xffaa0000),
          offset: Offset(2, -3),
          blurRadius: 1.5,
        ),
      ],
    ),
  ),
  c,
  scaler: scaler,
);

ForumBodyInlineEmphasisPaintBinding _phases(
  MixedEmphasisAllocatedSource s,
  ForumBodyParagraphCache c,
  TextScaler scaler,
) {
  final w = ForumBodyInlineEmphasisPaintPreparation(
    allocation: s.allocation,
    source: s.source,
    cache: c,
    expectedTextScaler: scaler,
    ensureOwner: () {},
    additionalOwnedLeases: () => [s.natural],
  );
  try {
    while (!w.isReady) {
      w.advance(maxParts: 32);
    }
    final binding = w.takeBinding();
    addTearDown(binding.close);
    return binding;
  } finally {
    w.close();
  }
}

List<ForumBodyInlinePaintRowView> _rows(
  MixedEmphasisAllocatedSource s, {
  ForumBodyInlineEmphasisPaintBinding? phases,
  void Function()? guard,
  int start = 0,
  int? end,
  Offset origin = Offset.zero,
}) => [
  for (var i = start; i < (end ?? s.allocation.rows.length); i++)
    if (phases == null)
      ForumBodyInlinePaintRowView.glyphs(
        parent: s.source,
        allocation: s.allocation,
        lineIndex: i,
        ensureOwner: guard ?? () {},
        allocationOrigin: origin,
      )
    else
      for (var j = 0; j < 3; j++)
        ForumBodyInlinePaintRowView.phase(
          parent: phases.phases[j],
          reference: phases.view.reference,
          lineIndex: i,
          layer: _layers[j],
          ensureOwner: guard ?? () {},
          allocationOrigin: origin,
        ),
];
ForumBodyTextPictureInput _input(List<ForumBodyInlinePaintRowView> rows) =>
    ForumBodyTextPictureInput(
      commands: [
        for (final r in rows)
          ForumBodyTextPictureCommand.fromInlineRow(r, Offset.zero),
      ],
      maxCommands: 8192,
    );

ForumBodyTextPicturePreparation _job(
  ForumBodyParagraphCache c,
  List<ForumBodyInlinePaintRowView> rows, {
  ForumBodyTextPictureInput? input,
  Iterable<ForumBodyEmphasisMarkLease> marks = const [],
  void Function()? guard,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
  bool immediate = false,
}) => immediate
    ? ForumBodyTextPicturePreparation(
        cache: c,
        input: input ?? _input(rows),
        text: const [],
        inlineRows: rows,
        marks: marks,
        ensureOwner: guard ?? () {},
        additionalOwnedLeases: owned,
      )
    : ForumBodyTextPicturePreparation.cooperative(
        cache: c,
        input: input ?? _input(rows),
        text: const [],
        inlineRows: rows,
        marks: marks,
        ensureOwner: guard ?? () {},
        additionalOwnedLeases: owned,
      );

({ForumBodyTextPictureLease picture, int parts}) _finish(
  ForumBodyTextPicturePreparation w,
  ForumBodyParagraphCache c, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var used = 0;
  try {
    for (var n = 0; !w.isReady; n++) {
      expect(n, lessThan(100000));
      final before = c.layoutBuildCount,
          step = w.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.picturesRecorded, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(w.cacheMiss, isFalse);
      expect(c.layoutBuildCount, before);
      used += step.partsPrepared;
    }
    return (picture: w.takeLease(), parts: used);
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
    expect(w.cacheMiss || step.waitingForLayoutBudget, isFalse);
  }
}

Future<List<int>> _pixels(ui.Picture picture, Size size, double dpr) async {
  final r = ui.PictureRecorder(),
      canvas = Canvas(r)
        ..scale(dpr)
        ..translate(30, 30);
  canvas.drawPicture(picture);
  final p = r.endRecording();
  try {
    final img = await p.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      return (await img.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  } finally {
    p.dispose();
  }
}

ui.Picture _record(void Function(Canvas) draw) {
  final r = ui.PictureRecorder();
  draw(Canvas(r));
  return r.endRecording();
}

void _control(
  Canvas canvas,
  MixedEmphasisAllocatedSource s, {
  ForumBodyInlineEmphasisPaintBinding? phases,
  int start = 0,
  int? end,
  Offset origin = Offset.zero,
}) {
  for (var i = start; i < (end ?? s.allocation.rows.length); i++) {
    if (phases != null) {
      for (final layer in _layers) {
        phases.view.paintPhaseRow(canvas, origin, i, layer);
      }
    } else {
      final row = s.allocation.input.rows.rows[i];
      if (row.isEmpty) continue;
      final shift = origin + s.allocation.rows[i].glyphOffset;
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      canvas.clipRect(
        Rect.fromLTRB(
          -16384,
          row.selector.clipTop,
          s.source.layout.width + 16384,
          row.selector.clipBottom,
        ),
        doAntiAlias: false,
      );
      s.source.layout.paintParent(canvas, Offset.zero);
      canvas.restore();
    }
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache c, int i) {
  final d = const ForumBodyParser().parse(
        html: '<p>inline-scene-pin$i</p>',
        sourceId: 'inline-scene-pin$i',
        conversionIdentity: 'none',
      ),
      styles = const ForumBodyStyleResolver().resolve(
        d,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: 'inline-pin',
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
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        for (final logical in [false, true]) {
          test(
            'actual physical inline scene $i/$direction/$scaler/$logical',
            () async {
              final c = _cache(),
                  s = _source(
                    c,
                    child: child,
                    direction: direction,
                    scaler: scaler,
                    logical: logical,
                  ),
                  phases = logical ? _phases(s, c, scaler) : null;
              if (!logical) c.prepareInlineParentPaint(s.source);
              final rows = _rows(s, phases: phases),
                  input = _input(rows),
                  before = c.activeLeases,
                  work = _job(c, rows, input: input);
              _bind(work);
              expect(work.nativeLeases.length, logical ? 3 : 1);
              expect(c.activeLeases, before + (logical ? 3 : 1));
              final picture = _finish(work, c, quantum: 512).picture,
                  reference = _record((cv) => _control(cv, s, phases: phases)),
                  actual = _record((cv) => picture.paint(cv, Offset.zero));
              try {
                final size = Size(250, s.allocation.height + 80);
                for (final dpr in [1.25, 3.0]) {
                  final expected = await _pixels(reference, size, dpr),
                      pixels = await _pixels(actual, size, dpr);
                  expect(expected.where((v) => v != 0), isNotEmpty);
                  expect(pixels, orderedEquals(expected));
                }
                expect(c.activeLeases, before + 1);
                final counts = (c.layoutBuildCount, c.pictureBuildCount),
                    warm = _finish(
                      _job(c, rows, input: input),
                      c,
                      cachedOnly: true,
                    ).picture;
                expect((c.layoutBuildCount, c.pictureBuildCount), counts);
                warm.release();
              } finally {
                reference.dispose();
                actual.dispose();
                picture.release();
              }
              expect(c.activeLeases, before);
            },
          );
        }
      }
    }
  }

  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      test(
        'physical parent phases and markers share one scene $direction/$scaler',
        () async {
          final c = _cache(),
              s = _source(
                c,
                logical: true,
                direction: direction,
                scaler: scaler,
                prefix:
                    '<span style="font-size:33px;text-emphasis:triangle;text-emphasis-position:under">P</span> Q Q Q ',
              ),
              b = _phases(s, c, scaler),
              rows = _rows(s, phases: b),
              mw = ForumBodyInlineEmphasisMarkerPreparation(
                allocation: s.allocation,
                natural: s.natural,
                cache: c,
                expectedTextScaler: scaler,
                ensureOwner: () {},
                additionalOwnedLeases: () => [s.source, ...b.nativeLeases],
              );
          late ForumBodyInlineEmphasisMarkerBinding markers;
          try {
            while (!mw.isReady) {
              mw.advance(maxParts: 1);
            }
            markers = mw.takeBinding();
          } finally {
            mw.close();
          }
          addTearDown(markers.close);
          final a = s.allocation,
              m = a.input.natural,
              placement = m.reflow.children.placement,
              byKey = {
                for (final font in markers.fonts)
                  font.nativeInputIdentity: font,
              },
              input = ForumBodyTextPictureInput(
                commands: [
                  for (var i = 0; i < a.rows.length; i++) ...[
                    for (final row in rows.where(
                      (r) => r.selector.lineIndex == i,
                    ))
                      ForumBodyTextPictureCommand.fromInlineRow(
                        row,
                        Offset.zero,
                      ),
                    for (var j = 0; j < a.marks.length; j++)
                      if (a.marks[j].lineIndex == i)
                        markers.pictureInput!.commands[j],
                  ],
                ],
                maxCommands: 8192,
              ),
              reference = _record((cv) {
                for (var i = 0; i < a.rows.length; i++) {
                  for (final layer in _layers) {
                    b.view.paintPhaseRow(cv, Offset.zero, i, layer);
                  }
                  for (final mark in placement.marks.where(
                    (mark) => mark.lineIndex == i,
                  )) {
                    final shift = a.rows[i].naturalOffset,
                        f = placement.input.fonts.fonts[mark.fontIndex];
                    cv.save();
                    cv.translate(shift.dx, shift.dy);
                    cv.translate(0, m.reflow.baselineDeltas[i]);
                    cv.translate(
                      mark.baselineOrigin.dx,
                      mark.baselineOrigin.dy,
                    );
                    byKey[f.nativeInputIdentity]!.layout.paint(
                      cv,
                      mark.fontOffset,
                    );
                    cv.restore();
                  }
                }
              }),
              work = _job(c, rows, input: input, marks: markers.fonts);
          _bind(work);
          expect(work.nativeLeases.length, 3 + markers.fonts.length);
          markers.close();
          b.close();
          s.natural.release();
          s.source.release();
          final picture = _finish(work, c).picture,
              actual = _record((cv) => picture.paint(cv, Offset.zero));
          try {
            c.clearUnpinned();
            expect(c.activeLeases, 1);
            expect(c.entryCount, 1);
            final size = Size(250, a.height + 80);
            for (final dpr in [1.25, 3.0]) {
              expect(
                await _pixels(actual, size, dpr),
                orderedEquals(await _pixels(reference, size, dpr)),
              );
            }
          } finally {
            picture.release();
            actual.dispose();
            reference.dispose();
          }
          expect(c.activeLeases, 0);
        },
      );
    }
  }

  test(
    'private aliases survive release of all borrowed sources after binding',
    () async {
      final c = _cache(),
          s = _source(c, logical: true),
          b = _phases(s, c, TextScaler.noScaling),
          rows = _rows(s, phases: b),
          reference = _record((cv) => _control(cv, s, phases: b)),
          work = _job(c, rows);
      _bind(work);
      b.close();
      s.natural.release();
      s.source.release();
      expect(c.activeLeases, 3);
      final picture = _finish(work, c).picture,
          recorded = _record((cv) => picture.paint(cv, Offset.zero));
      try {
        expect(c.activeLeases, 1);
        c.clearUnpinned();
        expect(c.entryCount, 1);
        final size = Size(250, s.allocation.height + 80);
        expect(
          await _pixels(recorded, size, 3),
          orderedEquals(await _pixels(reference, size, 3)),
        );
      } finally {
        picture.release();
        reference.dispose();
        recorded.dispose();
      }
      expect(c.activeLeases, 0);
    },
  );

  test(
    'inline picture metadata counts complete source once and each row separately',
    () {
      final c = _cache(), s = _source(c);
      c.prepareInlineParentPaint(s.source);
      final rows = _rows(s),
          first = _input([rows.first]),
          two = _input(rows.take(2).toList());
      expect(rows.length, greaterThan(1));
      expect(two.estimatedInputBytes - first.estimatedInputBytes, 256);
      expect(
        first.estimatedInputBytes,
        greaterThan(s.source.content.projection.display.text.length * 96),
      );
      final metadata =
          ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
            s.source.nativeInputIdentity,
          );
      expect(
        first.estimatedInputBytes,
        ForumBodyTextPictureInput.baseEstimatedInputBytes + 256 + metadata,
      );
      expect(two.commands.first.inlineRow, rows.first.selector);
    },
  );

  test(
    'long isolated coordinates use a bounded fragment origin, never scene slicing',
    () async {
      final c = _cache(),
          s = _source(
            c,
            prefix: 'P\n' * 160,
            suffix: '',
            style: 'text-emphasis:circle;line-height:.4;white-space:pre-wrap',
          ),
          index = s.allocation.rows.length - 1,
          origin = Offset(0, -s.allocation.rows[index].line.top);
      c.prepareInlineParentPaint(s.source);
      final rows = _rows(s, start: index, origin: origin), input = _input(rows);
      expect(rows.single.selector.nativeOffset.dy.abs(), greaterThan(32768));
      expect(input.commands.single.offset, Offset.zero);
      final picture = _finish(_job(c, rows), c).picture,
          reference = _record(
            (cv) => _control(cv, s, start: index, origin: origin),
          ),
          actual = _record((cv) => picture.paint(cv, Offset.zero));
      try {
        const size = Size(250, 140);
        expect(
          await _pixels(actual, size, 1.25),
          orderedEquals(await _pixels(reference, size, 1.25)),
        );
      } finally {
        picture.release();
        reference.dispose();
        actual.dispose();
      }
    },
  );

  test(
    'logical opaque backgrounds survive truly empty parent glyph rows',
    () async {
      final c = _cache(),
          s = _source(c, prefix: '', suffix: '', logical: true),
          b = _phases(s, c, TextScaler.noScaling),
          rows = _rows(s, phases: b);
      expect(rows[0].selector.isEmpty, isFalse);
      expect(rows[1].selector.isEmpty, isTrue);
      final glyphOnly = _finish(_job(c, [rows[1]]), c).picture,
          picture = _finish(_job(c, rows), c).picture,
          glyphRecord = _record((cv) => glyphOnly.paint(cv, Offset.zero)),
          actual = _record((cv) => picture.paint(cv, Offset.zero));
      try {
        const size = Size(250, 160);
        expect(
          (await _pixels(glyphRecord, size, 3)).every((v) => v == 0),
          isTrue,
        );
        expect(
          (await _pixels(actual, size, 3)).where((v) => v != 0),
          isNotEmpty,
        );
      } finally {
        glyphOnly.release();
        picture.release();
        glyphRecord.dispose();
        actual.dispose();
      }
    },
  );

  test(
    'raw path and mismatched physical/phase selectors cannot borrow authority',
    () {
      final c = _cache(),
          s = _source(c, logical: true),
          b = _phases(s, c, TextScaler.noScaling),
          rows = _rows(s, phases: b),
          before = c.activeLeases;
      expect(
        () => ForumBodyInlinePaintRowView.glyphs(
          parent: s.source,
          allocation: s.allocation,
          lineIndex: 0,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      expect(
        () => ForumBodyInlinePaintRowView.phase(
          parent: b.phases[0],
          reference: b.view.reference,
          lineIndex: 0,
          layer: ForumBodyParagraphPaintLayer.foreground,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: b.phases[1].nativeInputIdentity,
              offset: Offset.zero,
              inlineRow: rows[0].selector,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: b.phases[0].nativeInputIdentity,
              offset: Offset.zero,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(c.activeLeases, before);
    },
  );

  test(
    'unprepared, missing, unrequested and foreign rows release partial aliases',
    () {
      final c = _cache(),
          s = _source(c),
          unprepared = _rows(s),
          before = c.activeLeases;
      expect(() => _job(c, unprepared, immediate: true), throwsStateError);
      c.prepareInlineParentPaint(s.source);
      final rows = _rows(s), input = _input([rows.first]);
      expect(
        () => _job(c, [], input: input, immediate: true),
        throwsArgumentError,
      );
      expect(
        () => _job(c, rows, input: input, immediate: true),
        throwsArgumentError,
      );
      final other = _cache();
      expect(
        () => _job(other, [rows.first], input: input, immediate: true),
        throwsStateError,
      );
      expect(c.activeLeases, before);
    },
  );

  test('cached miss and immediate lookup reuse the same immutable scene', () {
    final c = _cache(), s = _source(c);
    c.prepareInlineParentPaint(s.source);
    final rows = _rows(s),
        input = _input(rows),
        before = c.activeLeases,
        work = _job(c, rows, input: input),
        counts = (c.layoutBuildCount, c.pictureBuildCount);
    for (var n = 0; !work.cacheMiss; n++) {
      expect(n, lessThan(10000));
      work.advance(maxParts: 1, cachedOnly: true);
    }
    expect((c.layoutBuildCount, c.pictureBuildCount), counts);
    final cold = _finish(work, c).picture,
        warmCounts = (c.layoutBuildCount, c.pictureBuildCount),
        warm = _finish(
          _job(c, rows, input: input, immediate: true),
          c,
          cachedOnly: true,
        ).picture;
    expect(warm.nativeInputIdentity, cold.nativeInputIdentity);
    expect((c.layoutBuildCount, c.pictureBuildCount), warmCounts);
    cold.release();
    warm.release();
    expect(c.activeLeases, before);
  });

  test(
    'external pins wait stably; caller-owned complete prefix cannot wait',
    () {
      final c = _cache(entries: 16), s = _source(c);
      c.prepareInlineParentPaint(s.source);
      c.clearUnpinned();
      final pins = [for (var i = 0; i < 14; i++) _pin(c, i)],
          rows = _rows(s),
          before = c.activeLeases,
          denied = _job(c, rows, owned: () => [s.natural, s.source, ...pins]);
      expect(
        () => _finish(denied, c),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(c.activeLeases, before);
      final work = _job(c, rows, owned: () => [s.natural, s.source]);
      for (var n = 0; ; n++) {
        expect(n, lessThan(10000));
        if (work.advance().waitingForLayoutBudget) break;
      }
      final counts = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases);
      for (var i = 0; i < 3; i++) {
        final step = work.advance();
        expect(step.waitingForLayoutBudget, isTrue);
        expect(step.partsPrepared, 0);
      }
      expect((c.layoutBuildCount, c.pictureBuildCount, c.activeLeases), counts);
      pins.first.release();
      _finish(work, c).picture.release();
      expect(c.activeLeases, before - 1);
    },
  );

  test(
    'each cooperative cancellation and alias-adoption retirement releases only own handles',
    () {
      final c = _cache(), s = _source(c);
      c.prepareInlineParentPaint(s.source);
      final rows = _rows(s),
          full = _finish(_job(c, rows), c),
          before = c.activeLeases - 1;
      full.picture.release();
      for (var stop = 0; stop <= full.parts; stop++) {
        final w = _job(c, rows);
        for (var n = 0; n < stop && !w.isReady; n++) {
          w.advance(maxParts: 1);
        }
        w.close();
        w.close();
        expect(c.activeLeases, before, reason: 'stop $stop');
      }
      ForumBodyTextPicturePreparation? active;
      var retired = false;
      final guarded = _rows(
        s,
        guard: () {
          if (active?.nativeLeases.isNotEmpty == true) {
            retired = true;
            active!.close();
          }
        },
      );
      active = _job(c, guarded);
      expect(() => _finish(active!, c), throwsStateError);
      expect(retired, isTrue);
      expect(c.activeLeases, before);
    },
  );
}
