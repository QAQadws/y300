import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const _dimension = PlaceholderDimensions(
  size: Size(40, 30),
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: 26,
);

ForumBodyParagraphCache _cache({int entries = 4}) =>
    ForumBodyParagraphCache(maxEntries: entries, maxEstimatedBytes: 1 << 22);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in [
    ForumBodyParagraphLayoutMode.wrap,
    ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  ]) {
    test(
      'native parent and shared child requests use one deduplicated footprint $mode',
      () {
        final input = mixedInlineInput();
        final band = ForumBodyTextBandContent(
          contexts: [input.base, input.annotation],
        );
        final base = ForumBodyTextRequest.bandChild(band: band, childIndex: 0);
        final annotation = ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: 1,
        );
        final page = ForumBodyInlinePageContent(
          content: input.content,
          dimensions: const [_dimension],
          rubyGroups: [
            ForumBodyRubyColumnRequest(base: base, annotation: annotation),
          ],
          layoutMode: mode,
        );
        final requests = <ForumBodyNativeRequest>[
          page.parentRequest,
          base,
          annotation,
        ];
        final cache = _cache(entries: 2);
        addTearDown(cache.close);
        final probe = cache.createBudgetProbe();
        try {
          for (final request in requests) {
            request.includeBudget(
              probe,
              width: 200,
              textScaler: TextScaler.noScaling,
            );
          }
          expect(cache.layoutBuildCount, 0);
          expect(cache.pictureBuildCount, 0);
          expect(cache.hitCount, 0);
          expect(cache.entryCount, 0);
          expect(cache.activeLeases, 0);
        } finally {
          probe.close();
        }
        final leases = <ForumBodyNativeParagraphLease>[];
        try {
          for (final request in requests) {
            leases.add(
              request.acquire(
                cache,
                width: 200,
                textScaler: TextScaler.noScaling,
                cachedOnly: false,
              )!,
            );
          }
          expect(cache.activeLeases, 3);
          expect(cache.entryCount, 2);
          expect(cache.layoutBuildCount, 2);
          expect(cache.pictureBuildCount, 0);
          final before = (
            cache.layoutBuildCount,
            cache.hitCount,
            cache.activeLeases,
            cache.budgetRevision,
            cache.estimatedRetainedBytes,
          );
          final warmProbe = cache.createBudgetProbe();
          try {
            for (final lease in leases) {
              warmProbe.includeLease(lease);
            }
            for (final request in requests) {
              request.includeBudget(
                warmProbe,
                width: 200,
                textScaler: TextScaler.noScaling,
              );
            }
          } finally {
            warmProbe.close();
          }
          expect((
            cache.layoutBuildCount,
            cache.hitCount,
            cache.activeLeases,
            cache.budgetRevision,
            cache.estimatedRetainedBytes,
          ), before);
        } finally {
          for (final lease in leases) {
            lease.release();
          }
        }
        expect(cache.activeLeases, 0);
        cache.clearUnpinned();
        expect(cache.estimatedRetainedBytes, 0);
      },
    );
  }

  test('a native parent cannot be omitted from a child-only footprint', () {
    final input = mixedInlineInput();
    final band = ForumBodyTextBandContent(
      contexts: [input.base, input.annotation],
    );
    final parent = ForumBodyInlineParagraphRequest(
      content: input.content,
      dimensions: const [_dimension],
      layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
    );
    final cache = _cache(entries: 1);
    addTearDown(cache.close);
    final probe = cache.createBudgetProbe();
    try {
      for (var i = 0; i < 2; i++) {
        ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: i,
        ).includeBudget(probe, width: 100, textScaler: TextScaler.noScaling);
      }
      expect(
        () => parent.includeBudget(
          probe,
          width: 100,
          textScaler: TextScaler.noScaling,
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      expect(cache.entryCount, 0);
      expect(cache.hitCount, 0);
      expect(cache.activeLeases, 0);
    } finally {
      probe.close();
    }
  });

  test(
    'parent requests freeze caller geometry and cached misses never shape',
    () {
      final input = mixedInlineInput();
      final dimensions = [_dimension];
      final request = ForumBodyInlineParagraphRequest(
        content: input.content,
        dimensions: dimensions,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      dimensions.clear();
      expect(request.content, same(input.content));
      expect(request.dimensions.single, _dimension);
      expect(() => request.dimensions.clear(), throwsUnsupportedError);
      final cache = _cache();
      addTearDown(cache.close);
      expect(
        request.acquire(
          cache,
          width: 100,
          textScaler: TextScaler.noScaling,
          cachedOnly: true,
        ),
        isNull,
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.pictureBuildCount, 0);
      final lease = request.acquire(
        cache,
        width: 100,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      final alias = request.acquire(
        cache,
        width: 30,
        textScaler: TextScaler.noScaling,
        cachedOnly: true,
      )!;
      try {
        expect(alias.layout, same(lease.layout));
        expect(alias.content, same(input.content));
        expect(alias.layout.width, greaterThan(30));
        expect(alias.layout.lines, hasLength(1));
        expect(alias.layout.dimensions.single, _dimension);
        expect(cache.layoutBuildCount, 1);
        final wrap = ForumBodyInlineParagraphRequest(
          content: input.content,
          dimensions: const [_dimension],
        );
        expect(
          wrap.acquire(
            cache,
            width: 100,
            textScaler: TextScaler.noScaling,
            cachedOnly: true,
          ),
          isNull,
        );
        expect(
          request.acquire(
            cache,
            width: 100,
            textScaler: TextScaler.linear(1.27),
            cachedOnly: true,
          ),
          isNull,
        );
        final changed = ForumBodyInlineParagraphRequest(
          content: input.content,
          dimensions: const [
            PlaceholderDimensions(
              size: Size(41, 30),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 26,
            ),
          ],
          layoutMode: request.layoutMode,
        );
        expect(
          changed.acquire(
            cache,
            width: 100,
            textScaler: TextScaler.noScaling,
            cachedOnly: true,
          ),
          isNull,
        );
        expect(cache.layoutBuildCount, 1);
      } finally {
        alias.release();
        lease.release();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'external pins reject a parent without taking ownership and retry after release',
    () {
      final input = mixedInlineInput();
      final cache = _cache(entries: 1);
      addTearDown(cache.close);
      final foreign = ForumBodyTextRequest.paragraph(input.contexts.first)
          .acquire(
            cache,
            width: 100,
            textScaler: TextScaler.noScaling,
            cachedOnly: false,
          )!;
      final parent = ForumBodyInlineParagraphRequest(
        content: input.content,
        dimensions: const [_dimension],
      );
      expect(
        () => parent.acquire(
          cache,
          width: 100,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect(foreign.isActive, isTrue);
      expect(cache.activeLeases, 1);
      foreign.release();
      final lease = parent.acquire(
        cache,
        width: 100,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      expect(cache.ownsLease(lease), isTrue);
      lease.releaseProvisional();
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 0);
    },
  );

  test(
    'shared child line hints cannot pretend to cover a second child line',
    () {
      final input = mixedInlineInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final cache = _cache();
      addTearDown(cache.close);
      final probe = cache.createBudgetProbe();
      try {
        expect(
          () => ForumBodyTextRequest.bandChild(band: band, childIndex: 0)
              .includeBudget(
                probe,
                width: 100,
                textScaler: TextScaler.noScaling,
                minimumLineCount: 2,
              ),
          throwsRangeError,
        );
        expect(cache.layoutBuildCount, 0);
        expect(cache.activeLeases, 0);
      } finally {
        probe.close();
      }
    },
  );
}
