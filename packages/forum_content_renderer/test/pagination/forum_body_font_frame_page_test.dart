import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(
    String html, {
    double lineHeight = .25,
    TextDirection direction = TextDirection.ltr,
  }) {
    cache = ForumBodyParagraphCache(maxEntries: 32, maxEstimatedBytes: 1 << 24);
    session = ForumBodyTextPageSession(
      document: const ForumBodyParser().parse(
        html: html,
        sourceId: 'font-frames',
        conversionIdentity: 'none',
      ),
      reader: ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          height: lineHeight,
        ),
        fontRevision: 'font-frame-ahem',
        textDirection: direction,
        linkColor: const Color(0xff0000ff),
        paragraphBefore: 0,
        paragraphAfter: 0,
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 20000,
        maxRuns: 1000,
        maxIssuedLeases: 64,
      ),
      layoutId: 'font-frames',
      width: 60,
      height: 24,
    );
    addTearDown(close);
  }
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void step() {
    final before = cache.layoutBuildCount;
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(cache.layoutBuildCount - before, lessThanOrEqualTo(1));
    expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }

  void finish() {
    for (var n = 0; !session.isComplete && n < 10000; n++) {
      step();
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    addTearDown(job.close);
    for (var n = 0; !job.isReady && n < 10000; n++) {
      job.advance(maxFragments: 1, maxParts: 1);
    }
    expect(job.isReady, isTrue);
    return job.takeFragments();
  }

  void close() {
    session.close();
    cache.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const html =
      '<p style="white-space:pre-wrap"><span style="color:red">AA</span><br>'
      '<span style="color:green">BB</span><br><span style="color:blue">CC</span></p>';
  for (final direction in TextDirection.values) {
    test(
      'tight ordinary rows paint complete own glyphs across pages, $direction',
      () async {
        final fixture = _Fixture(html, direction: direction)..finish();
        expect(fixture.session.snapshot.length, 3);
        final copied = StringBuffer();
        final colors = [
          const Color(0xffff0000),
          const Color(0xff008000),
          const Color(0xff0000ff),
        ];
        for (var page = 0; page < 3; page++) {
          final fragments = fixture.prepare(page);
          expect(fragments, hasLength(1));
          final binding = fragments.single as ForumBodyPreparedEmphasisFragment;
          final planned = fixture.session.snapshot[page].fragments.single;
          final text = binding.projection.text.substring(
            planned.coverageStartUtf16,
            planned.coverageEndUtf16,
          );
          copied.write(text);
          for (final g in binding.projection.graphemeRanges(
            startUtf16: planned.coverageStartUtf16,
            endUtf16: planned.coverageEndUtf16,
          )) {
            for (final box in binding.glyphBoxes(g.startUtf16, g.endUtf16)) {
              expect(box.top, greaterThanOrEqualTo(-1e-6));
              expect(box.bottom, lessThanOrEqualTo(planned.height + 1e-6));
            }
          }
          final recorder = ui.PictureRecorder();
          binding.view.paint(
            Canvas(recorder),
            Offset(planned.left, planned.top),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(60, 24);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var own = 0;
          for (var p = 0; p < pixels.length; p += 4) {
            if (pixels[p + 3] == 0) continue;
            final color = Color.fromARGB(
              pixels[p + 3],
              pixels[p],
              pixels[p + 1],
              pixels[p + 2],
            );
            expect(color, colors[page]);
            own++;
          }
          expect(
            own,
            800,
          ); // Two complete 20x20 Ahem glyphs, without neighbor ink.
          image.dispose();
          picture.dispose();
          binding.close();
        }
        expect(copied.toString(), 'AA\nBB\nCC');
        expect(fixture.session.activeIssuedLeases, 0);
      },
    );
  }
  test('non-overflowing text retains the ordinary paragraph path', () {
    final fixture = _Fixture('<p>AB</p>', lineHeight: 1.2)..finish();
    expect(
      fixture.session.snapshot[0].fragments.single.kind,
      ForumBodyTextPageFragmentKind.paragraph,
    );
    expect(fixture.cache.layoutBuildCount, 1);
  });
  test(
    'cancellation releases natural probe and partial allocated-row work',
    () {
      var completed = false;
      for (var stop = 0; stop < 2000; stop++) {
        final fixture = _Fixture('<p>AB CD EF</p>');
        for (var step = 0; step < stop && !fixture.session.isComplete; step++) {
          fixture.step();
        }
        completed = fixture.session.isComplete;
        fixture.close();
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.cache.estimatedRetainedBytes, 0);
        if (completed) break;
      }
      expect(completed, isTrue);
    },
  );
}
