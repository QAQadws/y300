import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

List<ForumBodyParagraphContent> contexts(
  List<String> roots, {
  TextStyle? textStyle,
}) {
  final document = const ForumBodyParser().parse(
    html: '<p>${roots.join()}</p>',
    sourceId: 'native-band-test',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle:
          textStyle ??
          const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
            color: Color(0xff000000),
          ),
      fontRevision: 'band-font',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return [
    for (var i = 0; i < roots.length; i++)
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0/$i',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      ),
  ];
}

Future<List<int>> raster(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(400, 400);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'each band context still checks scaler consistency on every admission',
    () {
      final input = ForumBodyTextBandContent(
        contexts: contexts(['<span>AB</span>', '<span>CD</span>']),
      );
      final seen = <double>[];
      var stable = false;
      final scaler = _Scaler((size) {
        seen.add(size);
        return stable ? size : size + seen.length;
      });
      Map<double, double> resolve() => ForumBodyTextBandLayout.validateInputs(
        content: input,
        textScaler: scaler,
      ).scales;
      expect(
        resolve,
        throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphLayoutFailure.scale,
          ),
        ),
      );
      expect(seen, [20, 20]);
      stable = true;
      for (var repeat = 0; repeat < 2; repeat++) {
        seen.clear();
        expect(resolve(), {20: 20});
        expect(seen, [20, 20]);
      }
    },
  );

  test(
    'a conflicting size does not hide a later scaler failure in the child',
    () {
      final input = ForumBodyTextBandContent(
        contexts: contexts([
          '<span>AB</span>',
          '<span>CD<i style="font-size:10px">xy</i></span>',
        ]),
      );
      final failure = StateError('scaler failed');
      final seen = <double>[];
      final scaler = _Scaler((size) {
        seen.add(size);
        if (size == 10) throw failure;
        return size + seen.length;
      });
      expect(
        () => ForumBodyTextBandLayout.validateInputs(
          content: input,
          textScaler: scaler,
        ),
        throwsA(same(failure)),
      );
      expect(seen, [20, 20, 10]);
    },
  );

  test(
    'different text and font sizes share one native band with independent geometry/source',
    () {
      final inputs = contexts([
        '<span>AB</span>',
        '<span style="font-size:10px">xy</span>',
        '<b>CD</b>',
      ]);
      final content = ForumBodyTextBandContent(contexts: inputs);
      final band = ForumBodyTextBandLayout.create(content: content);
      addTearDown(band.dispose);
      expect(band.children, hasLength(3));
      expect(band.lineCount, 5);
      for (var i = 0; i < inputs.length; i++) {
        final expected = ForumBodyParagraphLayout.create(
          content: inputs[i],
          width: 100,
        );
        try {
          final child = band.view(i);
          expect(child.width, closeTo(expected.width, 1e-3));
          expect(child.height, expected.height);
          expect(
            child.alphabeticBaseline,
            closeTo(expected.lines.single.baseline, 1e-3),
          );
          expect(child.projection, same(inputs[i].projection));
          final boxes = child.selectionBoxes(
            0,
            inputs[i].projection.text.length,
          );
          final original = expected.selectionBoxes(
            0,
            inputs[i].projection.text.length,
          );
          expect(boxes.length, original.length);
          for (var j = 0; j < boxes.length; j++) {
            expect(boxes[j].left, closeTo(original[j].left, 1e-3));
            expect(boxes[j].top, closeTo(original[j].top, 1e-3));
            expect(boxes[j].right, closeTo(original[j].right, 1e-3));
            expect(boxes[j].bottom, closeTo(original[j].bottom, 1e-3));
          }
          final hit = child.sourceAt(
            Offset(
              boxes.first.left + .1,
              (boxes.first.top + boxes.first.bottom) / 2,
            ),
          );
          expect(
            hit.sourceRune,
            inputs[i].projection.sourceAtUtf16(0).sourceRune,
          );
        } finally {
          expected.dispose();
        }
      }
      expect(() => band.children.clear(), throwsUnsupportedError);
    },
  );

  for (final (name, roots) in [
    (
      'mixed styles',
      [
        '<span>AB</span>',
        '<span style="font-size:10px">xy</span>',
        '<b>CD</b>',
      ],
    ),
    (
      'tight italic lines',
      [
        '<i style="line-height:0.25">AB</i>',
        '<span style="font-size:10px;line-height:0.25">xy</span>',
        '<span>YZ</span>',
      ],
    ),
    (
      'Unicode and preformatted spaces',
      [
        '<span style="white-space:pre"> A  </span>',
        '<span>e&#x301;👨‍👩‍👧‍👦</span>',
        '<span>tail</span>',
      ],
    ),
    (
      'RTL children',
      [
        '<span dir="rtl">אב</span>',
        '<span dir="rtl" style="font-size:10px">xy</span>',
        '<span dir="rtl">אבج</span>',
      ],
    ),
    (
      'tiny author line',
      ['<span style="line-height:0.01">AB</span>', '<span>tail</span>'],
    ),
  ]) {
    test(
      '$name pixels match independent paragraphs without sibling/spacer bleed',
      () async {
        final inputs = contexts(roots);
        final band = ForumBodyTextBandLayout.create(
          content: ForumBodyTextBandContent(contexts: inputs),
        );
        addTearDown(band.dispose);
        for (var i = 0; i < inputs.length; i++) {
          band.preparePaint(i);
        }
        final separate = [
          for (final input in inputs)
            ForumBodyParagraphLayout.create(content: input, width: 100),
        ];
        addTearDown(() {
          for (final layout in separate) {
            layout.dispose();
          }
        });
        final expected = await raster((canvas) {
          for (var i = 0; i < separate.length; i++) {
            separate[i].paint(canvas, Offset(30, 30 + i * 100));
          }
        });
        final actual = await raster((canvas) {
          for (var i = 0; i < inputs.length; i++) {
            band.view(i).paint(canvas, Offset(30, 30 + i * 100));
          }
        });
        var differences = 0;
        var firstDifference = -1;
        for (var byte = 0; byte < actual.length; byte++) {
          if (actual[byte] != expected[byte]) {
            differences++;
            if (firstDifference < 0) firstDifference = byte;
          }
        }
        expect(
          differences,
          0,
          reason: 'first differing RGBA byte $firstDifference',
        );
      },
    );
  }

  test(
    'nonlinear scaler applies only to real font inputs, never virtual separation',
    () {
      final inputs = contexts([
        '<span>AB</span>',
        '<span style="font-size:10px">xy</span>',
      ]);
      final seen = <double>{};
      final scaler = _Scaler((size) {
        seen.add(size);
        if (size == 20) return 30;
        if (size == 10) return 25;
        return double.nan;
      });
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(contexts: inputs),
        textScaler: scaler,
      );
      addTearDown(band.dispose);
      expect(seen, {20, 10});
      expect(band.gutter, 60);
      expect(band.view(0).width, 60);
      expect(band.view(1).width, 50);
      expect(band.view(0).height, 30);
      expect(band.view(1).height, 25);
    },
  );

  test(
    'fractional sizes preserve pixel-rounded heights and adjusted native baselines',
    () {
      final inputs = contexts(
        [
          '<span>AB</span>',
          '<span style="font-size:9.25px;line-height:1">xy</span>',
        ],
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 18.5,
          height: 1.5,
        ),
      );
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(contexts: inputs),
      );
      addTearDown(band.dispose);
      for (var i = 0; i < inputs.length; i++) {
        final expected = ForumBodyParagraphLayout.create(
          content: inputs[i],
          width: 100,
        );
        try {
          expect(band.view(i).height, expected.height);
          expect(
            band.view(i).alphabeticBaseline,
            closeTo(expected.lines.single.baseline, 1e-3),
          );
        } finally {
          expected.dispose();
        }
      }
    },
  );

  test(
    '64 unique children have distinct source views without 64 native resources',
    () {
      final inputs = contexts([
        for (var i = 0; i < 64; i++)
          '<span>漢${String.fromCharCode(0x4e00 + i)}</span>',
      ]);
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(contexts: inputs),
      );
      addTearDown(band.dispose);
      expect(band.children, hasLength(64));
      for (var i = 0; i < inputs.length; i++) {
        final child = band.view(i);
        final box = child.selectionBoxes(0, 1).first;
        expect(
          child
              .sourceAt(Offset(box.left + .1, (box.top + box.bottom) / 2))
              .sourceRune,
          i * 2,
        );
      }
    },
  );

  test(
    'a tiny author line retains native frame/font bounds and child-local hits',
    () {
      final inputs = contexts([
        '<span style="line-height:0.01">AB</span>',
        '<span>tail</span>',
      ]);
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(contexts: inputs),
      );
      addTearDown(band.dispose);
      final child = band.view(0);
      final original = ForumBodyParagraphLayout.create(
        content: inputs.first,
        width: 100,
      );
      addTearDown(original.dispose);
      expect(
        child.height,
        original.height,
        reason:
            'original ${original.lines.single.top}/${original.lines.single.bottom}/${original.lines.single.baseline} style ${inputs.first.style.textStyle.height}',
      );
      expect(child.geometry.fontBounds.height, greaterThan(0));
      final box = child.selectionBoxes(0, 1).first;
      expect(
        child
            .sourceAt(Offset(box.left + .1, (box.top + box.bottom) / 2))
            .sourceRune,
        0,
      );
      expect(
        child
            .sourceAt(Offset(box.right + .1, (box.top + box.bottom) / 2))
            .sourceRune,
        1,
      );
    },
  );

  test(
    'insufficient font isolation fails with a retry hint rather than clipping another child',
    () {
      final inputs = contexts([
        '<span style="line-height:0.25">AB</span>',
        '<span style="line-height:0.25">xy</span>',
      ]);
      ForumBodyTextBandLayoutException? failure;
      try {
        ForumBodyTextBandLayout.create(
          content: ForumBodyTextBandContent(contexts: inputs),
          gutter: 1,
        ).dispose();
      } on ForumBodyTextBandLayoutException catch (error) {
        failure = error;
      }
      expect(failure?.failure, ForumBodyTextBandLayoutFailure.isolation);
      expect(failure!.requiredGutter, greaterThan(1));
      final retry = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(contexts: inputs),
        gutter: failure.requiredGutter! + 1,
      );
      retry.dispose();
    },
  );

  test(
    'scope, structure, paint-effect and retained input budgets are explicit',
    () {
      final inputs = contexts(['<span>AB</span>', '<span>xy</span>']);
      for (final action in <void Function()>[
        () => ForumBodyTextBandContent(contexts: []),
        () => ForumBodyTextBandContent(contexts: inputs, maxChildren: 1),
        () => ForumBodyTextBandContent(contexts: inputs, maxRuns: 1),
        () => ForumBodyTextBandContent(contexts: contexts(['<span></span>'])),
        () => ForumBodyTextBandContent(
          contexts: contexts(['<span>AB</span>', '<span dir="rtl">אב</span>']),
        ),
        () => ForumBodyTextBandContent(
          contexts: [
            inputs[0],
            contexts(['<span>different</span>'])[0],
          ],
        ),
        () => ForumBodyTextBandContent(
          contexts: contexts(
            ['<span>AB</span>'],
            textStyle: const TextStyle(
              fontSize: 20,
              shadows: [Shadow(blurRadius: 10)],
            ),
          ),
        ),
        () => ForumBodyTextBandContent(
          contexts: contexts(
            ['<span>AB</span>'],
            textStyle: TextStyle(
              fontSize: 20,
              foreground: Paint()
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
            ),
          ),
        ),
        () => ForumBodyTextBandContent(
          contexts: contexts(
            ['<span>AB</span>'],
            textStyle: TextStyle(
              fontSize: 20,
              foreground: Paint()
                ..imageFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            ),
          ),
        ),
        () => ForumBodyTextBandContent(
          contexts: contexts(
            ['<span>AB</span>'],
            textStyle: TextStyle(
              fontSize: 20,
              foreground: Paint()..style = PaintingStyle.stroke,
            ),
          ),
        ),
      ]) {
        expect(action, throwsA(isA<ForumBodyParagraphInputException>()));
      }
      expect(
        () => ForumBodyTextBandContent(contexts: inputs, maxInputCodeUnits: 1),
        throwsA(isA<HtmlTextBandLimitException>()),
      );
      final band = ForumBodyTextBandContent(contexts: inputs);
      for (final gutter in [0.0, -1.0, double.nan, double.infinity, 16385.0]) {
        expect(
          () => ForumBodyTextBandLayout.create(content: band, gutter: gutter),
          throwsA(isA<ForumBodyTextBandLayoutException>()),
        );
      }
      final line = contexts(['<span>A<br>B</span>']);
      expect(
        () => ForumBodyTextBandLayout.create(
          content: ForumBodyTextBandContent(contexts: line),
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );

  test(
    'paint preparation is transactional, accounted and never performed by paint',
    () {
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(
          contexts: contexts(['<span>AB</span>', '<span>xy</span>']),
        ),
      );
      addTearDown(band.dispose);
      final child = band.view(0);
      expect(child.isPaintPrepared, isFalse);
      final recorder = ui.PictureRecorder();
      expect(
        () => child.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
      expect(band.approximatePictureBytes, 0);
      final rejected = band.recordPaint(0);
      expect(band.pendingPictureCount, 1);
      expect(band.preparedPictureCount, 0);
      expect(rejected.approximateBytes, greaterThan(0));
      expect(() => band.recordPaint(0), throwsStateError);
      rejected.close();
      rejected.close();
      expect(band.pendingPictureCount, 0);
      expect(band.approximatePictureBytes, 0);
      final accepted = band.recordPaint(0);
      band.adoptPaint(accepted);
      expect(accepted.isActive, isFalse);
      expect(band.pendingPictureCount, 0);
      expect(band.preparedPictureCount, 1);
      expect(child.isPaintPrepared, isTrue);
      final bytes = band.approximatePictureBytes;
      accepted.close();
      expect(band.preparePaint(0), isFalse);
      expect(band.approximatePictureBytes, bytes);
      final borrowed = band.recordPaint(1);
      expect(borrowed.recordsPicture, isFalse);
      expect(borrowed.approximateBytes, 0);
      expect(band.isPaintPrepared(1), isFalse);
      borrowed.close();
      expect(band.approximatePictureBytes, bytes);
      expect(band.preparePaint(1), isTrue);
      expect(band.preparedPictureCount, 1);
      final painted = ui.PictureRecorder();
      child.paint(Canvas(painted), Offset.zero);
      painted.endRecording().dispose();
      final previousDispose = ui.Picture.onDispose;
      var disposed = 0;
      ui.Picture.onDispose = (picture) {
        previousDispose?.call(picture);
        disposed++;
      };
      try {
        band.dispose();
      } finally {
        ui.Picture.onDispose = previousDispose;
      }
      expect(disposed, 1);
      expect(band.preparedPictureCount, 0);
      expect(band.approximatePictureBytes, 0);
      expect(child.isPaintPrepared, isFalse);
    },
  );

  test(
    'pending pictures retire with their owner and foreign adoption consumes only the ticket',
    () {
      final content = ForumBodyTextBandContent(
        contexts: contexts(['<span>AB</span>']),
      );
      final first = ForumBodyTextBandLayout.create(content: content);
      final second = ForumBodyTextBandLayout.create(content: content);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final foreign = first.recordPaint(0);
      expect(() => second.adoptPaint(foreign), throwsStateError);
      expect(foreign.isActive, isFalse);
      expect(first.pendingPictureCount, 0);
      expect(first.approximatePictureBytes, 0);
      expect(first.isDisposed, isFalse);
      final pending = first.recordPaint(0);
      first.dispose();
      expect(pending.isActive, isFalse);
      expect(first.pendingPictureCount, 0);
      expect(first.approximatePictureBytes, 0);
      pending.close();
      expect(second.isDisposed, isFalse);
    },
  );

  test('independent pending slots can still be admitted out of order', () {
    final band = ForumBodyTextBandLayout.create(
      content: ForumBodyTextBandContent(
        contexts: contexts(['<span>AB</span>', '<b>xy</b>', '<i>cd</i>']),
      ),
    );
    addTearDown(band.dispose);
    final first = band.recordPaint(0);
    final second = band.recordPaint(1);
    expect((first.recordsPicture, second.recordsPicture), (true, true));
    expect(band.pendingPictureCount, 2);
    final bytes = first.approximateBytes + second.approximateBytes;
    band.adoptPaint(second);
    expect((band.isPaintPrepared(0), band.isPaintPrepared(1)), (false, true));
    band.adoptPaint(first);
    expect(band.preparePaint(2), isTrue);
    expect(band.preparedPictureCount, 2);
    expect(band.pendingPictureCount, 0);
    expect(band.approximatePictureBytes, bytes);
  });

  test(
    'owner retirement inside Picture.onCreate releases the unadmitted allocation',
    () {
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(
          contexts: contexts(['<span>AB</span>']),
        ),
      );
      addTearDown(band.dispose);
      final previousCreate = ui.Picture.onCreate;
      final previousDispose = ui.Picture.onDispose;
      var created = 0;
      var disposed = 0;
      ui.Picture.onCreate = (picture) {
        previousCreate?.call(picture);
        created++;
        band.dispose();
      };
      ui.Picture.onDispose = (picture) {
        previousDispose?.call(picture);
        disposed++;
      };
      try {
        expect(() => band.recordPaint(0), throwsStateError);
        expect(created, 1);
        expect(disposed, 1);
        expect(band.pendingPictureCount, 0);
        expect(band.approximatePictureBytes, 0);
      } finally {
        ui.Picture.onCreate = previousCreate;
        ui.Picture.onDispose = previousDispose;
      }
    },
  );

  test(
    'disposing a view leaves siblings active; band retirement invalidates all native access',
    () {
      final band = ForumBodyTextBandLayout.create(
        content: ForumBodyTextBandContent(
          contexts: contexts(['<span>AB</span>', '<span>xy</span>']),
        ),
      );
      final first = band.view(0);
      final second = band.view(1);
      first.dispose();
      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isFalse);
      expect(() => first.sourceAt(Offset.zero), throwsStateError);
      expect(second.selectionBoxes(0, 1), isNotEmpty);
      band.dispose();
      band.dispose();
      expect(second.isDisposed, isTrue);
      expect(() => second.selectionBoxes(0, 1), throwsStateError);
      expect(() => second.sourceAt(Offset.zero), throwsStateError);
      expect(() => band.view(0), throwsStateError);
      final recorder = ui.PictureRecorder();
      expect(
        () => second.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);
  @override
  double get textScaleFactor => 1;
}
