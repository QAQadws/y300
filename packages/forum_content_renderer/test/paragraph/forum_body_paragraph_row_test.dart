import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  String text = 'ffi é 中 العربية 👩‍👩‍👧‍👦 ABC DEF GHI JKL',
  String kind = 'plain',
  TextDirection direction = TextDirection.ltr,
  bool indent = false,
}) {
  final html = switch (kind) {
    'mixed' => '$text <span style="font-size:31px;color:red">$text</span>',
    'background' =>
      '<span style="background-color:rgba(0,255,0,.4)">$text</span>',
    'decoration' => '<u>$text</u>',
    _ => text,
  };
  final doc = const ForumBodyParser().parse(
    html: '<p style="white-space:pre-wrap;line-height:.4">$html</p>',
    sourceId: 'paragraph-row',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: const Color(0xff123456),
          shadows: kind == 'shadow'
              ? const [
                  Shadow(
                    color: Color(0xffaa0000),
                    offset: Offset(2, -3),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
        fontRevision: 'row-ahem',
        linkColor: const Color(0xff0000ff),
        textDirection: direction,
        firstLineIndent: ForumBodyLength(
          indent ? 2 : 0,
          ForumBodyLengthUnit.em,
        ),
      ),
    ),
    path: '0',
  );
}

ForumBodyParagraphCache _cache({int entries = 8, int bytes = 1 << 24}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyParagraphRowMetrics _row(
  ForumBodyParagraphLease parent,
  int start, {
  int maxLines = 64,
  int maxBoxes = 4096,
  void Function()? owner,
}) {
  final job = ForumBodyParagraphRowPreparation(
    parent: parent,
    startLine: start,
    ensureOwner: owner ?? () {},
    maxLines: maxLines,
    maxBoxes: maxBoxes,
  );
  addTearDown(job.close);
  for (var steps = 0; !job.isReady && steps < 10000; steps++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  return job.takeMetrics();
}

List<ForumBodyParagraphRowView> _rows(ForumBodyParagraphLease parent) {
  final rows = <ForumBodyParagraphRowView>[];
  for (var line = 0; line < parent.layout.lineCount;) {
    final metrics = _row(parent, line);
    rows.add(
      ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: () {},
      ),
    );
    line = metrics.selector.endLine;
  }
  return rows;
}

TextStyle _clear(TextStyle style) => style.copyWith(
  foreground: Paint()..color = const Color(0x00000000),
  background: Paint()..color = const Color(0x00000000),
  shadows: const [],
  decoration: TextDecoration.none,
);

TextSpan _mask(TextSpan root, int start, int end) {
  final children = <InlineSpan>[];
  var offset = 0;
  for (final span in root.children!.cast<TextSpan>()) {
    final text = span.text!, style = span.style!;
    final stops = <int>{
      0,
      text.length,
      if (start > offset && start < offset + text.length) start - offset,
      if (end > offset && end < offset + text.length) end - offset,
    }.toList()..sort();
    var cursor = 0;
    for (final stop in stops.skip(1)) {
      children.add(
        TextSpan(
          text: text.substring(cursor, stop),
          style: offset + cursor >= start && offset + cursor < end
              ? style
              : _clear(style),
        ),
      );
      cursor = stop;
    }
    offset += text.length;
  }
  return TextSpan(style: root.style, children: children);
}

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  int dpr,
  int height,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr.toDouble()));
  final pic = rec.endRecording();
  try {
    final image = await pic.toImage(240 * dpr, height * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList(growable: false);
    } finally {
      image.dispose();
    }
  } finally {
    pic.dispose();
  }
}

ForumBodyTextPictureLease _scene(
  ForumBodyTextPicturePreparation job, {
  bool cachedOnly = false,
}) {
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 10000; i++) {
    final step = job.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.picturesRecorded, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
  }
  expect(job.isReady, isTrue);
  return job.takeLease();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final kind in [
      'plain',
      'mixed',
      'background',
      'decoration',
      'shadow',
    ]) {
      for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
        for (final dpr in [1, 3]) {
          test(
            'row scene preserves whole-context glyphs $direction/$kind/$scaler/DPR$dpr',
            () async {
              final content = _content(kind: kind, direction: direction),
                  cache = _cache(entries: 2);
              final parent = cache.acquire(
                content: content,
                width: 140,
                textScaler: scaler,
                rowIsolationPitch: 256,
              );
              addTearDown(parent.release);
              final rows = _rows(parent), refs = <TextPainter>[];
              expect(rows.length, greaterThan(2));
              expect(
                rows.map((r) => r.projection.text).join(),
                content.projection.text,
              );
              expect(cache.pictureBuildCount, 0);
              cache.prepareTextPaint(parent);
              final offsets = <Offset>[];
              var y = 20.0;
              for (final row in rows) {
                offsets.add(Offset(35, y));
                y += row.height + 8;
                final value = TextPainter(
                  text: _mask(
                    content.textSpan,
                    row.metrics.startUtf16,
                    row.metrics.endUtf16,
                  ),
                  textDirection: direction,
                  textAlign: content.style.textAlign,
                  textScaler: scaler,
                  strutStyle: StrutStyle.fromTextStyle(
                    content.style.textStyle,
                    height: 256 / scaler.scale(20),
                    leading: 0,
                    forceStrutHeight: true,
                  ),
                )..layout(minWidth: 140, maxWidth: 140);
                // Stage the oracle's first drawing just as the actual native resource is staged.
                final rec = ui.PictureRecorder();
                value.paint(Canvas(rec), Offset.zero);
                rec.endRecording().dispose();
                refs.add(value);
                final boxes = row.selectionBoxes(0, row.projection.text.length);
                final whole = parent.layout.selectionBoxes(
                  row.metrics.startUtf16,
                  row.metrics.endUtf16,
                );
                expect(boxes.length, whole.length);
                for (var i = 0; i < boxes.length; i++) {
                  expect(
                    boxes[i].toRect(),
                    whole[i].toRect().shift(Offset(0, -row.selector.originY)),
                  );
                  final hit = row.sourceAt(boxes[i].toRect().center);
                  final expected = parent.layout.sourceAt(
                    whole[i].toRect().center,
                  );
                  expect(hit.sourceRune, expected.sourceRune);
                  expect(
                    hit.displayUtf16 + row.metrics.startUtf16,
                    expected.displayUtf16,
                  );
                }
                expect(
                  row.sourceAt(const Offset(-10000, -10000)).displayUtf16,
                  inInclusiveRange(0, row.projection.text.length),
                );
              }
              addTearDown(() {
                for (final value in refs) {
                  value.dispose();
                }
              });
              final input = ForumBodyTextPictureInput(
                commands: [
                  for (var i = 0; i < rows.length; i++)
                    ForumBodyTextPictureCommand.fromParagraphRow(
                      rows[i],
                      offsets[i],
                    ),
                ],
              );
              final job = ForumBodyTextPicturePreparation(
                cache: cache,
                input: input,
                text: const [],
                paragraphRows: rows,
                ensureOwner: () {},
              );
              final scene = _scene(job);
              addTearDown(scene.release);
              expect(cache.layoutBuildCount, 1);
              expect(cache.pictureBuildCount, 2);
              expect(cache.preparedPictureCount, 1);
              final expected = await _pixels(
                (canvas) {
                  for (var i = 0; i < rows.length; i++) {
                    refs[i].paint(
                      canvas,
                      offsets[i] - Offset(0, rows[i].selector.originY),
                    );
                  }
                },
                dpr,
                y.ceil() + 25,
              );
              expect(
                await _pixels(
                  (canvas) => scene.paint(canvas, Offset.zero),
                  dpr,
                  y.ceil() + 25,
                ),
                expected,
              );
              parent.release();
              expect(rows.first.isDisposed, isTrue);
              expect(cache.activeLeases, 1);
              expect(
                await _pixels(
                  (canvas) => scene.paint(canvas, Offset.zero),
                  dpr,
                  y.ceil() + 25,
                ),
                expected,
              );
            },
          );
        }
      }
    }
  }

  test(
    'complete narrow graphemes group actual physical rows without source loss',
    () {
      final cache = _cache(),
          content = _content(text: '👩‍👩‍👧‍👦é👩‍👩‍👧‍👦');
      final parent = cache.acquire(
        content: content,
        width: 1,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final rows = _rows(parent);
      expect(rows.any((r) => r.metrics.lineCount > 1), isTrue);
      expect(
        rows.map((r) => r.projection.text).join(),
        content.projection.text,
      );
      expect(
        () => _row(parent, 0, maxLines: 1),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      expect(
        () => ForumBodyParagraphRowPreparation(
          parent: parent,
          startLine: 1,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'terminal empty row and first-line indent keep actual source and geometry',
    () {
      final cache = _cache(),
          content = _content(text: 'AB CD EF\n\n', indent: true);
      final parent = cache.acquire(
        content: content,
        width: 100,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final rows = _rows(parent);
      expect(rows.first.content.appliesFirstLineIndent, isTrue);
      expect(
        rows.skip(1).every((r) => !r.content.appliesFirstLineIndent),
        isTrue,
      );
      expect(rows.last.projection.text, '');
      expect(rows.last.metrics.startUtf16, content.projection.text.length);
      expect(rows.last.metrics.startUtf16, rows.last.metrics.endUtf16);
      expect(rows.last.selectionBoxes(0, 0), isEmpty);
      expect(
        rows.last.sourceAt(Offset.zero).sourceRune,
        content.projection
            .sourceAtUtf16(content.projection.text.length)
            .sourceRune,
      );
      expect(rows.last.height, greaterThanOrEqualTo(0));
      expect(() => rows.first.selectionBoxes(-1, 0), throwsRangeError);
      expect(
        () =>
            rows.first.selectionBoxes(0, rows.first.projection.text.length + 1),
        throwsRangeError,
      );
      expect(
        () => rows.first.sourceAt(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
    },
  );

  test('row source binding rejects equal mapping and stale native width', () {
    final cache = _cache(), content = _content();
    final parent = cache.acquire(
      content: content,
      width: 140,
      rowIsolationPitch: 160,
    );
    final clone = cache.acquire(
      content: content.displayWindow(
        startUtf16: 0,
        endUtf16: content.projection.text.length,
      ),
      width: 140,
      rowIsolationPitch: 160,
    );
    final otherWidth = cache.acquire(
      content: content,
      width: 130,
      rowIsolationPitch: 160,
    );
    final otherScale = cache.acquire(
      content: content,
      width: 140,
      rowIsolationPitch: 160,
      textScaler: const TextScaler.linear(1.27),
    );
    final otherPitch = cache.acquire(
      content: content,
      width: 140,
      rowIsolationPitch: 256,
    );
    final ordinary = cache.acquire(content: content, width: 140);
    addTearDown(parent.release);
    addTearDown(clone.release);
    addTearDown(otherWidth.release);
    addTearDown(otherScale.release);
    addTearDown(otherPitch.release);
    addTearDown(ordinary.release);
    final metrics = _row(parent, 0);
    expect(parent.nativeInputIdentity, clone.nativeInputIdentity);
    for (final current in [clone, otherWidth, otherScale, otherPitch]) {
      expect(
        () => ForumBodyParagraphRowView.bind(
          parent: current,
          metrics: metrics,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
    }
    expect(
      () => ForumBodyParagraphRowPreparation(
        parent: ordinary,
        startLine: 0,
        ensureOwner: () {},
      ),
      throwsA(isA<ForumBodyParagraphRowException>()),
    );
    parent.release();
    expect(
      () => ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: () {},
      ),
      throwsStateError,
    );
  });

  test(
    'insufficient isolation returns measured retry pitch and never reshapes',
    () {
      final cache = _cache(), content = _content(kind: 'mixed');
      final parent = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 25,
      );
      addTearDown(parent.release);
      double? required;
      try {
        _row(parent, 0);
      } on ForumBodyParagraphRowException catch (error) {
        expect(error.failure, ForumBodyParagraphRowFailure.isolation);
        required = error.requiredPitch;
      }
      expect(required, greaterThan(25));
      expect(cache.layoutBuildCount, 1);
      final retry = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: required,
      );
      addTearDown(retry.release);
      expect(_row(retry, 0).selector.endLine, 1);
      expect(cache.pictureBuildCount, 0);
    },
  );

  test(
    'geometry budgets and owner retirement preserve the borrowed handle',
    () {
      final cache = _cache(), content = _content();
      final parent = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      expect(
        () => _row(parent, 0, maxBoxes: 0),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
      var retired = false;
      final job = ForumBodyParagraphRowPreparation(
        parent: parent,
        startLine: 0,
        ensureOwner: () {
          if (retired) throw StateError('retired');
        },
      );
      job.advance(maxParts: 1);
      retired = true;
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(() => job.takeMetrics(), throwsStateError);
      expect(parent.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'scene rows pin aliases through a miss and record after caller release',
    () {
      final cache = _cache(), content = _content();
      final parent = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final rows = _rows(parent);
      final input = ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand.fromParagraphRow(rows[0], Offset.zero),
        ],
      );
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: cache,
          input: input,
          text: const [],
          paragraphRows: [rows[0]],
          ensureOwner: () {},
        ),
        throwsStateError,
      );
      cache.prepareTextPaint(parent);
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: cache,
          input: input,
          text: const [],
          paragraphRows: [rows[1]],
          ensureOwner: () {},
        ),
        throwsArgumentError,
      );
      final job = ForumBodyTextPicturePreparation(
        cache: cache,
        input: input,
        text: const [],
        paragraphRows: [rows[0]],
        ensureOwner: () {},
      );
      expect(cache.activeLeases, 2);
      parent.release();
      expect(rows[0].isDisposed, isTrue);
      expect(cache.activeLeases, 1);
      for (var i = 0; !job.cacheMiss && i < 20; i++) {
        job.advance(maxParts: 1, cachedOnly: true);
      }
      expect(job.cacheMiss, isTrue);
      expect(cache.pictureBuildCount, 1);
      final picture = _scene(job);
      expect(cache.activeLeases, 1);
      expect(cache.pictureBuildCount, 2);
      picture.release();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'row selectors distinguish whole text and cannot authorize forged geometry',
    () {
      final cache = _cache(), content = _content();
      final parent = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final rows = _rows(parent);
      cache.prepareTextPaint(parent);
      final foreign = _cache();
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: foreign,
          input: ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromParagraphRow(
                rows[0],
                Offset.zero,
              ),
            ],
          ),
          text: const [],
          paragraphRows: [rows[0]],
          ensureOwner: () {},
        ),
        throwsStateError,
      );
      expect(foreign.activeLeases, 0);
      final command = ForumBodyTextPictureCommand.fromParagraphRow(
        rows[0],
        Offset.zero,
      );
      final whole = ForumBodyTextPictureCommand.fromText(parent, Offset.zero);
      expect(command, isNot(whole));
      expect(
        command,
        isNot(
          ForumBodyTextPictureCommand.fromParagraphRow(rows[1], Offset.zero),
        ),
      );
      expect(
        ForumBodyTextPictureInput(commands: [command]).estimatedInputBytes,
        ForumBodyTextPictureInput(commands: [whole]).estimatedInputBytes + 64,
      );
      final selector = command.paragraphRow!;
      final forged = ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand(
            nativeInputIdentity: parent.nativeInputIdentity,
            offset: Offset.zero,
            paragraphRow: (
              startLine: selector.startLine,
              endLine: selector.endLine,
              originY: selector.originY + 1,
              clipTop: selector.clipTop,
              clipBottom: selector.clipBottom,
            ),
          ),
        ],
      );
      expect(
        () => ForumBodyTextPicturePreparation(
          cache: cache,
          input: forged,
          text: const [],
          paragraphRows: [rows[0]],
          ensureOwner: () {},
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity: parent.nativeInputIdentity,
              offset: Offset.zero,
              bandChildIndex: 0,
              paragraphRow: selector,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(cache.activeLeases, 1);
    },
  );

  for (final retireCache in [false, true]) {
    test(
      'row scene native callback retires aliases without late publication cache=$retireCache',
      () {
        final cache = _cache(), content = _content();
        final parent = cache.acquire(
          content: content,
          width: 140,
          rowIsolationPitch: 160,
        );
        addTearDown(parent.release);
        final row = _rows(parent).first;
        cache.prepareTextPaint(parent);
        final input = ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand.fromParagraphRow(row, Offset.zero),
          ],
        );
        final job = ForumBodyTextPicturePreparation(
          cache: cache,
          input: input,
          text: const [],
          paragraphRows: [row],
          ensureOwner: () {},
        );
        final oldCreate = ui.Picture.onCreate,
            oldDispose = ui.Picture.onDispose;
        var created = 0, disposed = 0;
        ui.Picture.onCreate = (_) {
          created++;
          if (retireCache) {
            cache.close();
          } else {
            job.close();
          }
        };
        ui.Picture.onDispose = (_) {
          disposed++;
        };
        try {
          expect(() => _scene(job), throwsStateError);
        } finally {
          ui.Picture.onCreate = oldCreate;
          ui.Picture.onDispose = oldDispose;
          job.close();
        }
        expect(created, 1);
        expect(disposed, 1);
        expect(cache.activeLeases, retireCache ? 0 : 1);
        expect(cache.preparedPictureCount, 0);
      },
    );
  }

  test(
    'cancelled geometry and scene transactions never consume caller handles',
    () {
      final cache = _cache(), content = _content();
      final parent = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final metrics = _row(parent, 0);
      var retired = false;
      expect(
        () => ForumBodyParagraphRowView.bind(
          parent: parent,
          metrics: metrics,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        ),
        returnsNormally,
      );
      final geometry = ForumBodyParagraphRowPreparation(
        parent: parent,
        startLine: 0,
        ensureOwner: () {},
      );
      while (!geometry.isReady) {
        geometry.advance(maxParts: 1);
      }
      geometry.close();
      expect(() => geometry.takeMetrics(), throwsStateError);
      final row = ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: () {
          if (retired) throw StateError('retired');
        },
      );
      cache.prepareTextPaint(parent);
      final input = ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand.fromParagraphRow(row, Offset.zero),
        ],
      );
      final job = ForumBodyTextPicturePreparation(
        cache: cache,
        input: input,
        text: const [],
        paragraphRows: [row],
        ensureOwner: () {},
      );
      job.advance(maxParts: 1);
      job.close();
      job.close();
      expect(cache.activeLeases, 1);
      retired = true;
      expect(() => row.sourceAt(Offset.zero), throwsStateError);
      expect(parent.isActive, isTrue);
    },
  );

  for (final dpr in [1, 3]) {
    test(
      'prepared row scenes conserve the prepared whole source including shadows DPR$dpr',
      () async {
        final cache = _cache(entries: 3), content = _content(kind: 'shadow');
        final parent = cache.acquire(
          content: content,
          width: 140,
          rowIsolationPitch: 160,
        );
        addTearDown(parent.release);
        final rows = _rows(parent);
        cache.prepareTextPaint(parent);
        final fragmented = _scene(
          ForumBodyTextPicturePreparation(
            cache: cache,
            input: ForumBodyTextPictureInput(
              commands: [
                for (final row in rows)
                  ForumBodyTextPictureCommand.fromParagraphRow(
                    row,
                    Offset(35, 25 + row.selector.originY),
                  ),
              ],
            ),
            text: const [],
            paragraphRows: rows,
            ensureOwner: () {},
          ),
        );
        addTearDown(fragmented.release);
        final whole = _scene(
          ForumBodyTextPicturePreparation(
            cache: cache,
            input: ForumBodyTextPictureInput(
              commands: [
                ForumBodyTextPictureCommand.fromText(
                  parent,
                  const Offset(35, 25),
                ),
              ],
            ),
            text: [parent],
            ensureOwner: () {},
          ),
        );
        addTearDown(whole.release);
        expect(
          await _pixels(
            (canvas) => fragmented.paint(canvas, Offset.zero),
            dpr,
            parent.layout.height.ceil() + 60,
          ),
          await _pixels(
            (canvas) => whole.paint(canvas, Offset.zero),
            dpr,
            parent.layout.height.ceil() + 60,
          ),
        );
        expect(cache.layoutBuildCount, 1);
        expect(cache.preparedPictureCount, 2);
      },
    );
  }
}
