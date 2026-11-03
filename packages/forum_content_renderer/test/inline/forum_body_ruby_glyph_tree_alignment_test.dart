import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

const _nested =
    '<ruby style="text-emphasis:circle"><rb><ruby>A<rt>in</rt></ruby></rb>'
    '<rt style="font-size:12px;text-emphasis:sesame">out</rt></ruby>';
const _mixed =
    '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb>'
    '<rt style="font-size:12px;text-emphasis:circle">out</rt></ruby>';
const _segment =
    '<ruby style="text-emphasis:circle"><rb>A</rb> <rb>B</rb>'
    '<rtc><rt style="font-size:12px">X</rt><rt style="font-size:12px">Y</rt></rtc></ruby>';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 20 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyRubyAtomMetrics _aligned(
  ForumBodyRubyAtomMetrics root,
  ForumBodyRubyAtomMetrics neighbor,
) {
  final union = ForumBodyRubyLevelUnion();
  for (final atom in [root, neighbor]) {
    final merge = union.mergeAtom(atom);
    while (!merge.isComplete) {
      expect(merge.advance(maxParts: 1), 1);
    }
  }
  final alignment = ForumBodyRubyAtomAlignment(
    atom: root,
    level: union.value,
    prepareResult: true,
  );
  while (!alignment.isComplete) {
    expect(alignment.advance(maxParts: 1), inInclusiveRange(1, 1));
  }
  return alignment.result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(
      maxEntries: 128,
      maxEstimatedBytes: 1 << 26,
    );
  });
  tearDown(() {
    expect(cache.activeLeases, 0);
    cache.close();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      for (final html in [_nested, _mixed, _segment]) {
        test('only aligned actual root moves $direction $scaler $html', () {
          ForumBodyRubyGlyphTreeMetrics measure(String html) =>
              rubyGlyphTreeBandsFixture(
                html,
                cache,
                direction: direction,
                scaler: scaler,
              ).geometry.metrics;
          final original = measure(html),
              neighbor = measure(
                html.replaceAll('font-size:12px', 'font-size:40px'),
              );
          final target = _aligned(original.rootAtom, neighbor.rootAtom);
          final counters = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.hitCount,
          );
          expect(original.withAlignedRoot(original.rootAtom), same(original));
          final current = original.withAlignedRoot(target);
          expect(current, isNot(same(original)));
          expect(current.input, same(original.input));
          expect(current.glyphTextScaler, same(original.glyphTextScaler));
          expect(current.glyphHandleCount, original.glyphHandleCount);
          expect(current.root.font, same(original.root.font));
          expect(
            current.root.backgroundFont,
            same(original.root.backgroundFont),
          );
          expect(
            current.box.bounds.height,
            greaterThan(original.box.bounds.height),
          );
          expect(current.nodes.length, original.nodes.length);
          for (var id = 0; id < current.nodes.length - 1; id++) {
            expect(current.nodes[id], same(original.nodes[id]));
          }
          expect(() => current.nodes.clear(), throwsUnsupportedError);
          switch ((original.rootAtom, target)) {
            case (
              ForumBodyRubyColumnMetrics(value: final old),
              ForumBodyRubyColumnMetrics(:final value),
            ):
              expect(old.hasSameMeasuredInput(value), isTrue);
              expect(current.root.group, same(value));
              expect(value.baseFontBounds, old.baseFontBounds);
              for (final (rank, annotation) in value.annotations.indexed) {
                expect(annotation.bounds, old.annotations[rank].bounds);
                expect(
                  annotation.fontBaseline,
                  old.annotations[rank].fontBaseline,
                );
              }
            case (
              ForumBodyRubyComponentMetrics(value: final old),
              ForumBodyRubyComponentMetrics(:final value),
            ):
              expect(old.hasSameMeasuredInput(value), isTrue);
              expect(current.root.segment, same(value));
              expect(value.columnWidths, orderedEquals(old.columnWidths));
            default:
              fail('Changed root kind');
          }
          final work = ForumBodyRubyGlyphTreeGeometryPreparation(
            metrics: current,
            ensureOwner: () {},
          );
          late ForumBodyRubyGlyphTreeGeometry geometry;
          try {
            while (!work.isReady) {
              expect(work.advance(maxParts: 1), 1);
            }
            geometry = work.takeGeometry();
          } finally {
            work.close();
          }
          expect(geometry.metrics, same(current));
          for (final source in original.input.sources) {
            expect(geometry.sourceForId(source.id).source, same(source));
          }
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.hitCount,
          ), counters);
        });
      }
    }
  }
  for (final html in [_nested, _segment]) {
    test(
      'equal foreign measurements cannot replace or realign the actual root $html',
      () {
        final original = rubyGlyphTreeBandsFixture(
          html,
          cache,
        ).geometry.metrics;
        final foreign = rubyGlyphTreeBandsFixture(html, cache).geometry.metrics;
        expect(original.box.bounds, foreign.box.bounds);
        expect(original.box.alphabeticBaseline, foreign.box.alphabeticBaseline);
        final counters = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
        );
        expect(
          () => original.withAlignedRoot(foreign.rootAtom),
          throwsArgumentError,
        );
        expect(
          () => original.withAlignedRoot(
            _aligned(foreign.rootAtom, original.rootAtom),
          ),
          throwsArgumentError,
        );
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
        ), counters);
      },
    );
  }
  test('alignment chains retain lineage after native cache owner closes', () {
    final original = rubyGlyphTreeBandsFixture(_nested, cache).geometry.metrics;
    final neighbor = rubyGlyphTreeBandsFixture(
      _nested.replaceAll('font-size:12px', 'font-size:40px'),
      cache,
    ).geometry.metrics;
    cache.close();
    final once = original.withAlignedRoot(
      _aligned(original.rootAtom, neighbor.rootAtom),
    );
    final twice = once.withAlignedRoot(
      _aligned(once.rootAtom, neighbor.rootAtom),
    );
    expect(twice.input, same(original.input));
    expect(
      twice.root.group!.hasSameMeasuredInput(original.root.group!),
      isTrue,
    );
    expect(twice.box.bounds, once.box.bounds);
    expect(twice.box.alphabeticBaseline, once.box.alphabeticBaseline);
    expect(twice.glyphTextScaler, same(original.glyphTextScaler));
  });
}
