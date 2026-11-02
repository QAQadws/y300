import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/paragraph/forum_body_text_request_preparation.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

ForumBodyParagraphContent _content({
  TextDirection direction = TextDirection.ltr,
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
  String? html,
  bool indent = false,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        html ??
        '<p style="line-height:.4">ffi é 中 العربية 👩‍👩‍👧‍👦 '
            '<span style="font-size:31px;color:red">AB 中</span> '
            'ffi é 中 العربية 👩‍👩‍👧‍👦</p>',
    sourceId: 'row-isolation',
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
      fontRevision: 'row-isolation-ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
      firstLineIndent: indent
          ? const ForumBodyLength(2, ForumBodyLengthUnit.em)
          : const ForumBodyLength(0, ForumBodyLengthUnit.em),
    ),
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
    layoutMode: mode,
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

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  int width,
  int height,
  int dpr,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width * dpr, height * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
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
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

final _isolationFailure = throwsA(
  isA<ForumBodyParagraphLayoutException>().having(
    (e) => e.failure,
    'failure',
    ForumBodyParagraphLayoutFailure.isolation,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [
      TextScaler.noScaling,
      const TextScaler.linear(1.27),
      const _Nonlinear(),
    ]) {
      for (final dpr in [1, 3]) {
        test(
          'one whole isolated native paragraph $direction/$scaler/DPR$dpr',
          () async {
            final content = _content(direction: direction), cache = _cache();
            final original = cache.acquire(
              content: content,
              width: 140,
              textScaler: scaler,
            );
            final request = ForumBodyTextRequest.paragraph(
              content,
              rowIsolationPitch: 160,
            );
            expect(
              request.acquire(
                cache,
                width: 140,
                textScaler: scaler,
                cachedOnly: true,
              ),
              isNull,
            );
            final lease =
                request.acquire(
                      cache,
                      width: 140,
                      textScaler: scaler,
                      cachedOnly: false,
                    )!
                    as ForumBodyParagraphLease;
            final layout = lease.layout;
            expect(lease.content, same(content));
            expect(layout.projection, same(content.projection));
            expect(layout.rowIsolationPitch, 160);
            expect(cache.layoutBuildCount, 2);
            expect(cache.pictureBuildCount, 0);
            expect(layout.isPaintPrepared, isFalse);
            expect(layout.lines.length, original.layout.lines.length);
            expect(layout.lines.length, greaterThan(2));
            for (var i = 0; i < layout.lines.length; i++) {
              final row = layout.lines[i], old = original.layout.lines[i];
              expect(
                (
                  row.startUtf16,
                  row.endUtf16,
                  row.coverageStartUtf16,
                  row.coverageEndUtf16,
                  row.engineStartUtf16,
                  row.engineEndUtf16,
                  row.canBreakBefore,
                  row.canBreakAfter,
                  row.left,
                  row.width,
                ),
                (
                  old.startUtf16,
                  old.endUtf16,
                  old.coverageStartUtf16,
                  old.coverageEndUtf16,
                  old.engineStartUtf16,
                  old.engineEndUtf16,
                  old.canBreakBefore,
                  old.canBreakAfter,
                  old.left,
                  old.width,
                ),
              );
              if (i > 0) {
                expect(
                  row.baseline - layout.lines[i - 1].baseline,
                  closeTo(160, .001),
                );
              }
            }
            // Independent raw native layout verifies the requested physical pitch
            // under the actual scaler; no per-row shaping or old-baseline offsets.
            final raw = TextPainter(
              text: content.textSpan,
              textDirection: direction,
              textAlign: content.style.textAlign,
              textScaler: scaler,
              locale: content.style.textStyle.locale,
              strutStyle: StrutStyle.fromTextStyle(
                content.style.textStyle,
                height: 160 / scaler.scale(20),
                leading: 0,
                forceStrutHeight: true,
              ),
            )..layout(minWidth: 140, maxWidth: 140);
            try {
              expect(layout.height, raw.height);
              final actualBoxes = layout.selectionBoxes(
                0,
                content.projection.text.length,
              );
              final expectedBoxes = raw.getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: content.projection.text.length,
                ),
              );
              expect(actualBoxes, expectedBoxes);
              for (final box in actualBoxes) {
                final point = box.toRect().center;
                final position = raw.getPositionForOffset(point);
                final expected = content.projection.sourceAtUtf16(
                  position.offset,
                  affinity: position.affinity == TextAffinity.upstream
                      ? HtmlProjectionAffinity.upstream
                      : HtmlProjectionAffinity.downstream,
                );
                final actual = layout.sourceAt(point);
                expect(
                  (actual.sourceRune, actual.displayUtf16, actual.isExact),
                  (
                    expected.sourceRune,
                    expected.displayUtf16,
                    expected.isExact,
                  ),
                );
              }
              final before = (cache.layoutBuildCount, cache.pictureBuildCount);
              expect(cache.prepareTextPaint(lease), isTrue);
              expect(cache.prepareTextPaint(lease), isFalse);
              expect(cache.preparedPictureCount, 0);
              expect(
                await _pixels(
                  (canvas) => layout.paint(canvas, const Offset(20, 20)),
                  180,
                  layout.height.ceil() + 40,
                  dpr,
                ),
                await _pixels(
                  (canvas) => raw.paint(canvas, const Offset(20, 20)),
                  180,
                  layout.height.ceil() + 40,
                  dpr,
                ),
              );
              expect(
                (cache.layoutBuildCount, cache.pictureBuildCount),
                (before.$1, before.$2 + 1),
              );
            } finally {
              raw.dispose();
            }
            expect(() => layout.fragment(0, 1), _isolationFailure);
            expect(
              () => layout.lineWindow(ForumBodyParagraphWindow.full),
              _isolationFailure,
            );
            final warm = request.acquire(
              cache,
              width: 140,
              textScaler: scaler,
              cachedOnly: true,
            )!;
            expect(warm.layout, same(layout));
            warm.release();
            original.release();
            lease.release();
            expect(cache.activeLeases, 0);
          },
        );
      }
    }
    test(
      'isolation preserves actual indent and negative tracking $direction',
      () {
        final content = _content(
          direction: direction,
          indent: true,
          html: '<p style="letter-spacing:-4px">AB CD EF GH IJ KL</p>',
        );
        final cache = _cache();
        final original = cache.acquire(content: content, width: 90);
        final isolated = cache.acquire(
          content: content,
          width: 90,
          rowIsolationPitch: 120,
        );
        expect(
          isolated.layout.firstLineIndent.appliedAdvance,
          original.layout.firstLineIndent.appliedAdvance,
        );
        expect(
          isolated.layout.horizontalInset,
          original.layout.horizontalInset,
        );
        expect(isolated.layout.lines.length, original.layout.lines.length);
        for (var i = 0; i < isolated.layout.lines.length; i++) {
          final a = isolated.layout.lines[i], b = original.layout.lines[i];
          expect(
            (
              a.left,
              a.width,
              a.coverageStartUtf16,
              a.coverageEndUtf16,
              a.engineCoverageStartUtf16,
              a.engineCoverageEndUtf16,
            ),
            (
              b.left,
              b.width,
              b.coverageStartUtf16,
              b.coverageEndUtf16,
              b.engineCoverageStartUtf16,
              b.engineCoverageEndUtf16,
            ),
          );
        }
        final box = isolated.layout.selectionBoxes(0, 1).single.toRect();
        final hit = isolated.layout.sourceAt(box.center);
        expect(hit.sourceRune, inInclusiveRange(0, 1));
        isolated.release();
        original.release();
      },
    );
  }

  test(
    'pitch participates in native keys, probes and retained scene input',
    () {
      final content = _content(), cache = _cache();
      final leases = <ForumBodyParagraphLease>[];
      final probe = cache.createBudgetProbe(captureInputEstimates: true);
      for (final pitch in [null, 160.0, 240.0]) {
        final lease = cache.acquire(
          content: content,
          width: 140,
          rowIsolationPitch: pitch,
        );
        leases.add(lease);
        final request = ForumBodyTextRequest.paragraph(
          content,
          rowIsolationPitch: pitch,
        );
        request.includeBudget(
          probe,
          width: 140,
          textScaler: TextScaler.noScaling,
          minimumLineCount: lease.layout.lineCount,
        );
        probe.includeLease(lease);
        request.includeBudget(
          probe,
          width: 140,
          textScaler: TextScaler.noScaling,
          minimumLineCount: lease.layout.lineCount,
        );
        final warm = request.acquire(
          cache,
          width: 140,
          textScaler: TextScaler.noScaling,
          cachedOnly: true,
        )!;
        expect(warm.nativeInputIdentity, lease.nativeInputIdentity);
        warm.release();
      }
      final estimates = probe.snapshotNativeEstimates();
      expect(estimates, hasLength(3));
      for (var i = 0; i < leases.length; i++) {
        expect(estimates[i].identity, leases[i].nativeInputIdentity);
        expect(
          estimates[i].estimatedBytes,
          leases[i].nativeLayoutEstimatedBytes,
        );
      }
      final inputs = [
        for (final lease in leases)
          ForumBodyTextPictureInput(
            commands: [
              ForumBodyTextPictureCommand.fromText(lease, Offset.zero),
            ],
          ),
      ];
      expect(inputs.toSet(), hasLength(3));
      expect(inputs[1].estimatedInputBytes - inputs[0].estimatedInputBytes, 32);
      expect(inputs[2].estimatedInputBytes, inputs[1].estimatedInputBytes);
      probe.close();
      for (final lease in leases) {
        lease.release();
      }
      cache.close();
      expect(estimates[1].estimatedBytes, greaterThan(0));
    },
  );

  test(
    'one cache admits and evicts whole isolated requests with ordinary pins',
    () {
      final content = _content(), cache = _cache(entries: 1);
      final ordinary = cache.acquire(content: content, width: 140);
      expect(
        () =>
            cache.acquire(content: content, width: 140, rowIsolationPitch: 160),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 1);
      ordinary.release();
      final isolated = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      expect(cache.tryAcquireCached(content: content, width: 140), isNull);
      expect(cache.layoutBuildCount, 2);
      expect(cache.entryCount, 1);
      isolated.release();
      cache.close();
      expect(() => isolated.layout, throwsStateError);
    },
  );

  for (final pitch in [double.nan, double.infinity, 0.0, -1.0, 16385.0]) {
    test('invalid native isolation pitch rejects before scaling $pitch', () {
      final content = _content(), cache = _cache();
      final scaler = _CallbackScaler(
        (_) => throw StateError('Unexpected scaling'),
      );
      final probe = cache.createBudgetProbe();
      expect(
        () => cache.tryAcquireCached(
          content: content,
          width: 140,
          rowIsolationPitch: pitch,
          textScaler: scaler,
        ),
        _isolationFailure,
      );
      expect(
        () => ForumBodyTextRequest.paragraph(
          content,
          rowIsolationPitch: pitch,
        ).includeBudget(probe, width: 140, textScaler: scaler),
        _isolationFailure,
      );
      probe.close();
      expect(cache.entryCount, 0);
      expect(cache.layoutBuildCount, 0);
    });
  }
  for (final mode in [
    ForumBodyParagraphLayoutMode.intrinsicSingleLine,
    ForumBodyParagraphLayoutMode.fitSingleLine,
  ]) {
    test('single-line layout modes cannot request row isolation $mode', () {
      final content = _content(mode: mode), cache = _cache();
      expect(
        () =>
            cache.acquire(content: content, width: 140, rowIsolationPitch: 160),
        _isolationFailure,
      );
      expect(cache.layoutBuildCount, 0);
    });
  }
  test(
    'excessive isolated height fails without retaining a partial resource',
    () {
      final content = _content(html: '<p>${'A<br>' * 80}</p>'),
          cache = _cache();
      expect(
        () => cache.acquire(
          content: content,
          width: 140,
          rowIsolationPitch: 16384,
        ),
        _isolationFailure,
      );
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 0);
      expect(cache.layoutBuildCount, 0);
      final valid = cache.acquire(
        content: content,
        width: 140,
        rowIsolationPitch: 160,
      );
      expect(valid.layout.height, lessThan(1048576));
      valid.release();
    },
  );
  for (final retireAt in [1, 5]) {
    test(
      'scaler retirement cannot install isolated resources at call $retireAt',
      () {
        final content = _content(), cache = _cache();
        var calls = 0;
        final scaler = _CallbackScaler((size) {
          if (++calls == retireAt) cache.close();
          return size;
        });
        expect(
          () => cache.acquire(
            content: content,
            width: 140,
            rowIsolationPitch: 160,
            textScaler: scaler,
          ),
          throwsStateError,
        );
        expect(calls, greaterThanOrEqualTo(retireAt));
        expect(cache.entryCount, 0);
        expect(cache.activeLeases, 0);
      },
    );
  }
  test('isolation does not bypass active-emphasis source qualification', () {
    final content = _content(
          html: '<p style="text-emphasis:filled dot">ABC</p>',
        ),
        cache = _cache();
    expect(
      () => cache.acquire(content: content, width: 140, rowIsolationPitch: 160),
      throwsA(
        isA<ForumBodyParagraphLayoutException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphLayoutFailure.emphasis,
        ),
      ),
    );
    expect(cache.layoutBuildCount, 0);
  });

  test(
    'measurement retains no drawing and cached-only visible work cannot preflight',
    () {
      final content = _content(), cache = _cache(entries: 1);
      final request = ForumBodyTextRequest.paragraph(
        content,
        rowIsolationPitch: 160,
      );
      final measure = ForumBodyTextRequestPreparation(
        cache: cache,
        request: request,
        ensureOwner: () {},
        preparePaint: false,
        width: 140,
      );
      measure.advance();
      expect(measure.isReady, isTrue);
      final measured = measure.takeLease();
      expect(measured.layout.isPaintPrepared, isFalse);
      expect(cache.pictureBuildCount, 0);
      final recorder = ui.PictureRecorder();
      expect(
        () => measured.layout.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
      final visible = ForumBodyTextRequestPreparation(
        cache: cache,
        request: request,
        ensureOwner: () {},
        preparePaint: true,
        width: 140,
      );
      final cold = visible.advance(cachedOnly: true);
      expect(cold.cacheMiss, isTrue);
      expect(visible.isReady, isFalse);
      expect(cache.pictureBuildCount, 0);
      final bytes = cache.estimatedRetainedBytes;
      final step = visible.advance();
      expect(step.units, 1);
      expect(visible.isReady, isTrue);
      final prepared = visible.takeLease();
      expect(prepared.layout, same(measured.layout));
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 1);
      expect(cache.preparedPictureCount, 0);
      expect(cache.estimatedRetainedBytes, bytes);
      prepared.release();
      measured.release();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'new visible request yields between shaping and first native drawing',
    () {
      final content = _content(), cache = _cache();
      final job = ForumBodyTextRequestPreparation(
        cache: cache,
        request: ForumBodyTextRequest.paragraph(
          content,
          rowIsolationPitch: 160,
        ),
        ensureOwner: () {},
        preparePaint: true,
        width: 140,
      );
      job.advance();
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
      expect(job.isReady, isFalse);
      job.advance();
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 1);
      expect(job.isReady, isTrue);
      job.takeLease().release();
    },
  );

  test('cancelling after shape does not record or keep a font alias', () {
    final cache = _cache();
    final job = ForumBodyTextRequestPreparation(
      cache: cache,
      request: ForumBodyTextRequest.paragraph(
        _content(),
        rowIsolationPitch: 160,
      ),
      ensureOwner: () {},
      preparePaint: true,
      width: 140,
    );
    job.advance();
    job.close();
    expect(cache.layoutBuildCount, 1);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
    expect(job.takeLease, throwsStateError);
  });

  for (final onCreate in [false, true]) {
    test(
      'preflight callback retirement releases its transient picture create=$onCreate',
      () {
        final cache = _cache();
        final lease = cache.acquire(
          content: _content(),
          width: 140,
          rowIsolationPitch: 160,
        );
        final layout = lease.layout;
        final oldCreate = ui.Picture.onCreate,
            oldDispose = ui.Picture.onDispose;
        var created = 0, disposed = 0;
        ui.Picture.onCreate = (_) {
          created++;
          if (onCreate) cache.close();
        };
        ui.Picture.onDispose = (_) {
          disposed++;
          if (!onCreate) cache.close();
        };
        try {
          expect(() => cache.prepareTextPaint(lease), throwsStateError);
        } finally {
          ui.Picture.onCreate = oldCreate;
          ui.Picture.onDispose = oldDispose;
          lease.release();
        }
        expect(created, 1);
        expect(disposed, 1);
        expect(layout.isDisposed, isTrue);
        expect(layout.isPaintPrepared, isFalse);
        expect(cache.entryCount, 0);
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'preflight reentry cannot record another picture or retire its caller',
    () {
      final cache = _cache();
      final lease = cache.acquire(
        content: _content(),
        width: 140,
        rowIsolationPitch: 160,
      );
      final oldCreate = ui.Picture.onCreate, oldDispose = ui.Picture.onDispose;
      var created = 0, disposed = 0;
      ui.Picture.onCreate = (_) {
        created++;
        expect(() => cache.prepareTextPaint(lease), throwsStateError);
      };
      ui.Picture.onDispose = (_) {
        disposed++;
        cache.clearUnpinned();
      };
      try {
        expect(cache.prepareTextPaint(lease), isTrue);
      } finally {
        ui.Picture.onCreate = oldCreate;
        ui.Picture.onDispose = oldDispose;
      }
      expect(created, 1);
      expect(disposed, 1);
      expect(lease.layout.isPaintPrepared, isTrue);
      expect(cache.pictureBuildCount, 1);
      expect(cache.entryCount, 1);
      expect(cache.activeLeases, 1);
      lease.release();
    },
  );
}
