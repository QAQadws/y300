import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_layout_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_flowability_inspector.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_layout_policy_resolver.dart';

void main() {
  const resolver = DefaultNovelReaderPaginationLayoutPolicyResolver();
  const inspector = DefaultNovelReaderComplexHtmlFlowabilityInspector();

  group('pagination layout policy resolver', () {
    test('assigns every route an explicit capability policy', () {
      final policies =
          <NovelReaderPaginationRoute, NovelReaderPaginationLayoutPolicy>{
            for (final route in NovelReaderPaginationRoute.values)
              route: resolver.resolve(route),
          };

      expect(policies.keys, unorderedEquals(NovelReaderPaginationRoute.values));
      _expectPolicy(
        policies[NovelReaderPaginationRoute.safeText]!,
        measure: NovelReaderPaginationMeasurePolicy.textPainter,
        split: NovelReaderPaginationSplitPolicy.lineRanges,
        placement: NovelReaderPaginationPlacementPolicy.flow,
        overflow: NovelReaderPaginationOverflowPolicy.minimumTextFragment,
        keepPageOpen: true,
      );
      for (final route in const <NovelReaderPaginationRoute>[
        NovelReaderPaginationRoute.flowableComplexText,
        NovelReaderPaginationRoute.rubyInline,
      ]) {
        _expectPolicy(
          policies[route]!,
          measure: NovelReaderPaginationMeasurePolicy.htmlRendererRange,
          split: NovelReaderPaginationSplitPolicy.domBoundaries,
          placement: NovelReaderPaginationPlacementPolicy.flow,
          overflow: NovelReaderPaginationOverflowPolicy.fallbackToVertical,
          keepPageOpen: true,
        );
      }
      for (final route in const <NovelReaderPaginationRoute>[
        NovelReaderPaginationRoute.isolatedImage,
        NovelReaderPaginationRoute.tableBlock,
        NovelReaderPaginationRoute.collapseBlock,
      ]) {
        _expectPolicy(
          policies[route]!,
          measure: NovelReaderPaginationMeasurePolicy.htmlRendererWholeAtom,
          split: NovelReaderPaginationSplitPolicy.none,
          placement: NovelReaderPaginationPlacementPolicy.dedicatedPage,
          overflow: NovelReaderPaginationOverflowPolicy.innerScroll,
          keepPageOpen: false,
        );
      }
      for (final route in const <NovelReaderPaginationRoute>[
        NovelReaderPaginationRoute.atomicWidget,
        NovelReaderPaginationRoute.complexHtml,
      ]) {
        _expectPolicy(
          policies[route]!,
          measure: NovelReaderPaginationMeasurePolicy.htmlRendererWholeAtom,
          split: NovelReaderPaginationSplitPolicy.none,
          placement: NovelReaderPaginationPlacementPolicy.dedicatedPage,
          overflow: NovelReaderPaginationOverflowPolicy.innerScroll,
          keepPageOpen: false,
        );
      }
    });
  });

  group('complex HTML flowability inspector', () {
    test('keeps text-bearing unknown wrappers and styles flowable', () {
      for (final html in const <String>[
        '<article data-legacy="1">未知 wrapper 正文</article>',
        '<font face="Uninstalled Fantasy Font">未知字体正文</font>',
        '<span style="padding:20px">复杂样式正文</span>',
      ]) {
        final result = inspector.inspect(html);

        expect(result.isTextBearing, isTrue, reason: html);
        expect(result.isMonotonic, isTrue, reason: html);
        expect(result.isFlowable, isTrue, reason: html);
        expect(result.failure, isNull, reason: html);
      }
    });

    test('marks ruby as a protected but flowable text boundary', () {
      final result = inspector.inspect('<p>前<ruby>字<rt>じ</rt></ruby>后</p>');

      expect(result.isFlowable, isTrue);
      expect(result.hasProtectedInlineNodes, isTrue);
      expect(result.requiresRubyBoundaries, isTrue);
    });

    test('rejects dedicated content from range pagination', () {
      for (final html in const <String>[
        '<table><tr><td>正文</td></tr></table>',
        '<div class="showcollapse_box"><div>正文</div></div>',
      ]) {
        final result = inspector.inspect(html);

        expect(result.isFlowable, isFalse, reason: html);
        expect(
          result.failure,
          NovelReaderComplexHtmlFlowabilityFailure.containsDedicatedContent,
          reason: html,
        );
      }
    });

    test('rejects embedded widgets even when they contain no text', () {
      for (final html in const <String>[
        '<iframe src="about:blank"></iframe>',
        '<video src="video.mp4"></video>',
        '<audio src="audio.mp3"></audio>',
        '<canvas></canvas>',
        '<p>前<img src="image.jpg">后</p>',
      ]) {
        final result = inspector.inspect(html);

        expect(result.isFlowable, isFalse, reason: html);
        expect(
          result.failure,
          NovelReaderComplexHtmlFlowabilityFailure.containsAtomicWidget,
          reason: html,
        );
      }
    });

    test('rejects script-driven and non-monotonic layouts', () {
      final script = inspector.inspect('<script>layout()</script>');
      final eventHandler = inspector.inspect('<p onclick="go()">正文</p>');
      final positioned = inspector.inspect(
        '<div style="position:absolute">正文</div>',
      );

      expect(
        script.failure,
        NovelReaderComplexHtmlFlowabilityFailure.containsScriptedLayout,
      );
      expect(
        eventHandler.failure,
        NovelReaderComplexHtmlFlowabilityFailure.containsScriptedLayout,
      );
      expect(
        positioned.failure,
        NovelReaderComplexHtmlFlowabilityFailure.containsNonMonotonicStyle,
      );
    });

    test('does not treat whitespace-only markup as flowable text', () {
      final result = inspector.inspect('<div>\n &nbsp;　</div>');

      expect(result.isTextBearing, isFalse);
      expect(result.isFlowable, isFalse);
      expect(
        result.failure,
        NovelReaderComplexHtmlFlowabilityFailure.noRenderableText,
      );
    });
  });
}

void _expectPolicy(
  NovelReaderPaginationLayoutPolicy policy, {
  required NovelReaderPaginationMeasurePolicy measure,
  required NovelReaderPaginationSplitPolicy split,
  required NovelReaderPaginationPlacementPolicy placement,
  required NovelReaderPaginationOverflowPolicy overflow,
  required bool keepPageOpen,
}) {
  expect(policy.measure, measure);
  expect(policy.split, split);
  expect(policy.placement, placement);
  expect(policy.overflow, overflow);
  expect(policy.keepPageOpenAfterAppend, keepPageOpen);
  expect(policy.isBreakable, split != NovelReaderPaginationSplitPolicy.none);
  expect(
    policy.isDedicated,
    placement == NovelReaderPaginationPlacementPolicy.dedicatedPage,
  );
}
