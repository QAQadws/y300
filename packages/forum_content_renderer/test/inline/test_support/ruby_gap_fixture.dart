import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';

final class RubyGapFixture {
  RubyGapFixture({
    required this.direction,
    this.scaler = TextScaler.noScaling,
    bool tight = false,
    double gapSize = 40,
    double? annotationGapSize,
    bool includeBaseGap = true,
    String position = 'alternate',
  }) {
    final h = tight ? '.25' : '1';
    final baseGap = includeBaseGap
        ? '<span style="font-size:${gapSize}px;line-height:$h;text-decoration:underline"> </span>'
        : '';
    final annotationGap = annotationGapSize == null
        ? ''
        : '<span style="font-size:${annotationGapSize}px;line-height:$h;text-decoration:underline"> </span>';
    final doc = const ForumBodyParser().parse(
      html:
          '<p dir="${direction.name}"><ruby style="ruby-position:$position"><rb style="font-size:20px;line-height:$h">A</rb>$baseGap<rb style="font-size:30px;line-height:$h">B</rb><rtc><rt style="font-size:10px;line-height:$h">x</rt>$annotationGap<rt style="font-size:15px;line-height:$h">y</rt></rtc><rtc style="font-size:10px;line-height:$h">abcdefghij</rtc></ruby></p>',
      sourceId: 'actual-base-gap',
      conversionIdentity: 'none',
    );
    final flow = ForumBodyTextFlowCursor(
      document: doc,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1);
        if (flow.current case ForumBodyTextFlowInline(:final content)) {
          input = ForumBodyInlinePlanInput(content, 300);
          break;
        }
      }
    } finally {
      flow.close();
    }
    request = (input.atoms.single as ForumBodyRubySegmentAtomRequest).value;
  }
  final TextDirection direction;
  final TextScaler scaler;
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  late final ForumBodyInlinePlanInput input;
  late final ForumBodyRubySegmentRequest request;
  ForumBodyRubySegmentMetrics measure(int q) {
    final job = ForumBodyRubySegmentMetricsPreparation(
      cache: cache,
      request: request,
      ensureOwner: () {},
      textScaler: scaler,
    );
    try {
      for (var i = 0; !job.isReady && i < 10000; i++) {
        final step = job.advance(maxParts: q);
        expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
        expect(step.layoutsBuilt, lessThanOrEqualTo(1));
        expect(step.picturesBuilt, 0);
      }
      expect(job.isReady, isTrue);
      return job.takeMetrics();
    } finally {
      job.close();
    }
  }

  ForumBodyRubySegmentLayout prepare(
    ForumBodyRubySegmentMetrics metrics,
    int q,
  ) {
    final job = ForumBodyRubySegmentPreparation(
      cache: cache,
      request: request,
      metrics: metrics,
      ensureOwner: () {},
      textScaler: scaler,
    );
    try {
      for (var i = 0; !job.isReady && i < 10000; i++) {
        final step = job.advance(maxParts: q);
        expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      }
      expect(job.isReady, isTrue);
      return job.takeLayout();
    } finally {
      job.close();
    }
  }

  void close() => cache.close();
}

Future<List<int>> rubyGapPixels(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(3);
  draw(canvas);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(600, 420);
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
