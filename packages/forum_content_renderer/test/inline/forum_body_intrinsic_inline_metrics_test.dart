import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_inline_page_preparation.dart';

ForumBodyInlinePlanInput _input({
  ForumBodyParagraphLayoutMode mode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  TextDirection direction = TextDirection.ltr,
}) {
  final document = const ForumBodyParser().parse(
    html: '<p>H<sup style="color:red">2</sup>O</p>',
    sourceId: 'intrinsic-word',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyTextFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'intrinsic-word',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  try {
    while (!flow.isComplete) {
      flow.advance(maxEvents: 1);
      if (flow.current case ForumBodyTextFlowInline(:final content)) {
        return ForumBodyInlinePlanInput(
          ForumBodyInlineFlowContent(
            identity: content.identity,
            path: content.path,
            fontRevision: content.fontRevision,
            styleRevision: content.styleRevision,
            style: content.style,
            layoutMode: mode,
            appliesFirstLineIndent: false,
            parts: content.parts,
            ignored: content.ignored,
            issues: content.issues,
          ),
          40,
        );
      }
    }
    throw StateError('Missing mixed source');
  } finally {
    flow.close();
  }
}

ForumBodyInlinePlanPreparation _open(
  ForumBodyInlinePlanInput input,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
  void Function()? guard,
}) => ForumBodyInlinePlanPreparation(
  input: input,
  cache: cache,
  textScaler: scaler,
  ensureOwner: guard ?? () {},
);

void _finish(
  ForumBodyInlinePlanPreparation work,
  ForumBodyParagraphCache cache,
) {
  for (var i = 0; !work.isReady; i++) {
    expect(i, lessThan(10000));
    final builds = cache.layoutBuildCount;
    final step = work.advance(maxParts: 1);
    expect(step.partsPrepared, inInclusiveRange(0, 1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
    expect(cache.pictureBuildCount, 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Curve()]) {
      test(
        'neutral intrinsic box retains native text/source: $direction/$scaler',
        () {
          final input = _input(direction: direction);
          final cache = ForumBodyParagraphCache(
            maxEntries: 32,
            maxEstimatedBytes: 1 << 24,
          );
          addTearDown(cache.close);
          final work = _open(input, cache, scaler: scaler);
          addTearDown(work.close);
          _finish(work, cache);
          final builds = cache.layoutBuildCount;
          final metrics = work.takeIntrinsicBox();
          expect(cache.activeLeases, 0);
          expect(cache.layoutBuildCount, builds);
          expect(cache.pictureBuildCount, 0);
          expect(metrics.size.width, greaterThan(40));
          expect(metrics.fragment.coverageStartUtf16, 0);
          expect(metrics.fragment.coverageEndUtf16, 3);
          expect(metrics.input.content.projection.display.text, 'H2O');
          expect(
            metrics.input.content.contexts.map((c) => c.content.style.role),
            everyElement(ForumBodyTextRole.body),
          );
          expect(metrics.nativeHandleCount, 2);
          expect(() => work.takeIntrinsicBox(), throwsStateError);
          final visible = ForumBodyInlinePagePreparation(
            input: metrics.input,
            fragment: metrics.fragment,
            identity: input.content.identity,
            cache: cache,
            textScaler: scaler,
            ensureOwner: () {},
            ownedPageLeases: () => const [],
          );
          addTearDown(visible.close);
          ForumBodyInlineParagraphView? view;
          for (var i = 0; view == null; i++) {
            expect(i, lessThan(10000));
            final before = (cache.layoutBuildCount, cache.pictureBuildCount);
            view = visible.advance(maxParts: 1, cachedOnly: false).view;
            expect(
              cache.layoutBuildCount -
                  before.$1 +
                  cache.pictureBuildCount -
                  before.$2,
              lessThanOrEqualTo(1),
            );
          }
          try {
            expect(view.width, metrics.size.width);
            expect(view.height, metrics.size.height);
            expect(view.lines.single.baseline, metrics.baseline);
            for (final c in view.content.contexts) {
              if (c.startUtf16 == c.endUtf16) continue;
              final box = view
                  .glyphBoxes(c.startUtf16, c.endUtf16)
                  .first
                  .toRect();
              final hit = view.sourceHitAt(box.center);
              expect(hit.window, same(c));
              expect(hit.position.isExact, isTrue);
              final selected = forumBodyTextSelectionAt(
                binding: ForumBodyPreparedTextFragment.inline(view),
                fragment: metrics.fragment,
                pageSize: metrics.size,
                point: box.center,
              );
              expect(selected?.text, c.content.projection.text);
              expect(selected?.isAnnotation, isFalse);
            }
          } finally {
            view.close();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }
  test('wrap transfer is rejected without consuming the normal ready plan', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 32,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final work = _open(_input(mode: ForumBodyParagraphLayoutMode.wrap), cache);
    addTearDown(work.close);
    _finish(work, cache);
    expect(() => work.takeIntrinsicBox(), throwsStateError);
    expect(work.isReady, isTrue);
    final normal = work.take();
    normal.lease.release();
    expect(cache.activeLeases, 0);
  });
  test(
    'ready owner retirement releases the parent instead of publishing a box',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 32,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      var current = true;
      final work = _open(
        _input(),
        cache,
        guard: () {
          if (!current) throw StateError('retired');
        },
      );
      addTearDown(work.close);
      _finish(work, cache);
      current = false;
      expect(() => work.takeIntrinsicBox(), throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );
  test('cold cached-only miss continues through the same intrinsic plan', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 32,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final work = _open(_input(), cache);
    addTearDown(work.close);
    for (var i = 0; !work.cacheMiss; i++) {
      expect(i, lessThan(10000));
      work.advance(maxParts: 1, cachedOnly: true);
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
    }
    _finish(work, cache);
    expect(
      work.takeIntrinsicBox().input.content.projection.display.text,
      'H2O',
    );
    expect(cache.activeLeases, 0);
  });
}

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 18 ? 1.6 : 1.2);
  @override
  double get textScaleFactor => 1.2;
}
