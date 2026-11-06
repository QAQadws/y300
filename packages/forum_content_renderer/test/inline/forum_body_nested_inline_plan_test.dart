import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_source_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_atom_request.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_layout.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart';

import 'test_support/unprojected_ruby_fixture.dart';

ForumBodyInlineFlowContent _flow(String html) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'nested-inline-plan',
    conversionIdentity: 'none',
  );
  final reader = ForumBodyReaderStyle(
    textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
    fontRevision: 'nested-ahem',
    linkColor: const Color(0xff0000ff),
  );
  final cursor = ForumBodyTextFlowCursor(document: doc, reader: reader);
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        return withAuthoredRubies(content, readAuthoredRubies(doc, reader));
      }
    }
    throw StateError('Missing inline flow');
  } finally {
    cursor.close();
  }
}

ForumBodyInlinePlanInput _input(String html) {
  final source = ForumBodyInlineSourcePreparation(
    input: _flow(html),
    width: 100,
    ensureOwner: () {},
  );
  try {
    while (!source.isReady) {
      source.advance(maxParts: 1);
    }
    return source.takeInput();
  } finally {
    source.close();
  }
}

ForumBodyParagraphCache _cache() =>
    ForumBodyParagraphCache(maxEntries: 64, maxEstimatedBytes: 1 << 24);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deep structural compilation spends the caller source allowance', () {
    var html = 'A';
    for (var depth = 0; depth < 30; depth++) {
      html =
          '<ruby style="font-size:20px"><rb>$html</rb><rt style="font-size:1px">x</rt></ruby>';
    }
    final source = ForumBodyInlineSourcePreparation(
      input: _flow(html),
      width: 100,
      ensureOwner: () {},
    );
    var calls = 0;
    while (!source.isReady) {
      expect(source.advance(maxParts: 1), 1);
      calls++;
    }
    final input = source.takeInput();
    expect(calls, greaterThan(30));
    expect(input.atoms.single, isA<ForumBodyRubyTreeAtomRequest>());
    expect(input.atoms.single.nativeRequests, hasLength(31));
    expect(
      input.content.projection.display.text,
      'A${List.filled(30, 'x').join()}',
    );
    expect(() => source.advance(maxParts: 1), throwsStateError);
    source.close();
  });

  test(
    'a later tree band retry rebinds earlier planned inputs without losing geometry',
    () {
      final input = _input(
        '<span><ruby dir="ltr"><rb><ruby>AB<rt>xy</rt></ruby></rb><rt>zz</rt></ruby>'
        '<ruby dir="rtl" style="line-height:.25"><rb style="line-height:.25">'
        '<ruby style="line-height:.25">CD<rt style="line-height:.25">uv</rt></ruby></rb>'
        '<rt style="line-height:.25">ww</rt></ruby></span>',
      );
      expect(input.atoms, hasLength(2));
      final first = (input.atoms.first as ForumBodyRubyTreeAtomRequest).value;
      final second = input.atoms.last as ForumBodyRubyTreeAtomRequest;
      final band =
          (second.nativeRequests.first as ForumBodyTextBandChildRequest).band;
      input.replaceBand(band, 1);
      final cache = _cache();
      final work = ForumBodyInlinePlanPreparation(
        input: input,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      try {
        for (var calls = 0; !work.isReady && calls < 10000; calls++) {
          final step = work.advance(maxParts: 1);
          expect(step.partsPrepared, lessThanOrEqualTo(1));
          expect(step.waitingForLayoutBudget, isFalse);
        }
        final current =
            input.atoms.last.nativeRequests.first
                as ForumBodyTextBandChildRequest;
        expect(current.gutter, greaterThan(1));
        final ready = work.take();
        try {
          final plans = ready.content.rubyAtoms
              .cast<ForumBodyRubyTreePlan>()
              .toList();
          expect(identical(plans.first.request, first), isFalse);
          expect(plans.first.request.hasSameStructure(first), isTrue);
          for (final plan in plans) {
            expect(plan.metrics.input, same(plan.request));
          }
          expect(ready.lease.layout.dimensions, ready.content.dimensions);
        } finally {
          ready.lease.release();
        }
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
        cache.close();
      }
    },
  );

  test(
    'a root-only effective scale change is rejected before visible native work',
    () {
      final input =
          (_input(
                    '<ruby style="font-size:30px"><rb style="font-size:20px">'
                    '<ruby style="font-size:20px">A<rt style="font-size:10px">x</rt></ruby></rb>'
                    '<rt style="font-size:8px">y</rt></ruby>',
                  ).atoms.single
                  as ForumBodyRubyTreeAtomRequest)
              .value;
      final planning = _cache();
      final metricWork = ForumBodyRubyTreeMetricsPreparation(
        input: input,
        cache: planning,
        ensureOwner: () {},
      );
      while (!metricWork.isReady) {
        metricWork.advance(maxParts: 1);
      }
      final metrics = metricWork.takeMetrics();
      metricWork.close();
      planning.close();
      expect(metrics.effectiveScales[30], 30);
      final visible = _cache();
      final work = ForumBodyRubyTreePreparation(
        input: input,
        metrics: metrics,
        cache: visible,
        ensureOwner: () {},
        expectedTextScaler: const _RootScaler(),
      );
      try {
        expect(
          () {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          },
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.scale,
            ),
          ),
        );
        expect(visible.layoutBuildCount, 0);
        expect(visible.activeLeases, 0);
        expect(work.nativeLeases, isEmpty);
      } finally {
        work.close();
        visible.close();
      }
    },
  );
}

final class _RootScaler extends TextScaler {
  const _RootScaler();
  @override
  double scale(double size) => size == 30 ? 60 : size;
  @override
  double get textScaleFactor => 1;
}
