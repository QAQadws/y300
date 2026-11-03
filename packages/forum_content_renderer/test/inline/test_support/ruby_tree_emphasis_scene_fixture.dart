import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'ruby_glyph_tree_fixture.dart';

const rubyTreeEmphasisSceneNested =
    '<ruby style="text-emphasis:\'X\' red;background:#ff000080;line-height:.4">'
    '<rb><ruby style="background:#0000ff80"><rb>A é</rb>'
    '<rt style="font-size:18px"></rt></ruby></rb>'
    '<rt style="text-emphasis:\'Y\' blue">out</rt></ruby>';
const rubyTreeEmphasisSceneMixed =
    '<ruby style="background:#ff000080"><rb>L<ruby>A<rt>x</rt></ruby>R</rb>'
    '<rt style="text-emphasis:circle blue">z</rt></ruby>';
const rubyTreeEmphasisSceneSegment =
    '<ruby style="ruby-position:under;text-emphasis:circle;'
    'text-emphasis-position:under"><rb>A</rb> <rb style="font-size:24px">B</rb>'
    '<rtc><rt style="font-size:32px"></rt> <rt>b</rt></rtc></ruby>';

final class RubyTreeEmphasisSceneFixture {
  RubyTreeEmphasisSceneFixture(
    String html, {
    this.direction = TextDirection.ltr,
    this.scaler = TextScaler.noScaling,
    ForumBodyRubyGlyphTreeInput Function(ForumBodyRubyGlyphTreeInput)? mapInput,
  }) {
    cache = ForumBodyParagraphCache(
      maxEntries: 512,
      maxEstimatedBytes: 1 << 26,
    );
    addTearDown(() {
      expect(cache.activeLeases, 0);
      cache.close();
    });
    plan = rubyTreeEmphasisPlanFixture(
      html,
      cache,
      direction: direction,
      scaler: scaler,
      mapInput: mapInput,
    );
  }
  final TextDirection direction;
  final TextScaler scaler;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyRubyTreeEmphasisPlan plan;
  ForumBodyRubyGlyphTreeInput get input =>
      plan.placement.input.input.geometry.metrics.input;
  ForumBodyRubyTreeEmphasisScenePreparation open({
    ForumBodyParagraphCache? targetCache,
    ForumBodyRubyGlyphTreeInput? currentInput,
    double? width,
    TextScaler? expectedScaler,
    void Function()? owner,
    void Function()? visibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? prefix,
  }) => ForumBodyRubyTreeEmphasisScenePreparation(
    input: currentInput ?? input,
    plan: plan,
    cache: targetCache ?? cache,
    ensureOwner: owner ?? () {},
    ensureVisibleOwner: visibleOwner,
    width: width ?? input.maxWidth,
    expectedTextScaler: expectedScaler ?? scaler,
    additionalOwnedLeases: prefix,
  );

  ForumBodyRubyTreeEmphasisLayout finish(
    ForumBodyRubyTreeEmphasisScenePreparation work, {
    bool cachedOnly = false,
    int quantum = 1,
  }) {
    try {
      for (var n = 0; !work.isReady; n++) {
        expect(n, lessThan(40000));
        final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
        expect(step.partsPrepared, inInclusiveRange(1, quantum));
        expect(
          step.nativeLayoutsBuilt + step.picturesRecorded,
          lessThanOrEqualTo(1),
        );
        expect(step.waitingForLayoutBudget, isFalse);
        expect(work.cacheMiss, isFalse);
      }
      return work.takeLayout();
    } finally {
      work.close();
    }
  }
}
