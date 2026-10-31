import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_page_preparation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pure input snapshots dimensions/requests and counts actual visible handles without native work',
    () {
      final fixture = MixedPagePreparationFixture();
      addTearDown(fixture.close);
      final input = fixture.input;
      expect(
        input.textCodeUnits,
        fixture.content.projection.display.text.length,
      );
      expect(input.runCount, fixture.content.runs.length);
      expect(
        input.nativeHandleCountFor(fixture.snapshot.first.fragments.single),
        7,
      );
      expect(
        input.nativeHandleCountFor(fixture.snapshot.last.fragments.single),
        3,
      );
      expect(() => input.dimensions.clear(), throwsUnsupportedError);
      expect(() => input.rubyGroups.clear(), throwsUnsupportedError);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.pictureBuildCount, 0);
    },
  );

  test(
    'stale equal-text contexts and incomplete atom requests cannot bind current input',
    () {
      final current = MixedPagePreparationFixture();
      addTearDown(current.close);
      final old = MixedPagePreparationFixture();
      addTearDown(old.close);
      expect(
        () => ForumBodyInlinePageContent(
          content: current.content,
          dimensions: current.input.dimensions,
          rubyGroups: old.input.rubyGroups,
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
      expect(
        () => ForumBodyInlinePageContent(
          content: current.content,
          dimensions: current.input.dimensions,
          rubyGroups: current.input.rubyGroups.take(3).toList(),
        ),
        throwsArgumentError,
      );
      expect(current.cache.activeLeases, 0);
    },
  );

  test(
    'a full band outside the retained parent cannot evade input budgets',
    () {
      final fixture = MixedPagePreparationFixture();
      addTearDown(fixture.close);
      final subset = ForumBodyInlineSpanContent.compose(
        identity: fixture.content.identity,
        path: 'subset',
        fontRevision: fixture.content.fontRevision,
        styleRevision: fixture.content.styleRevision,
        style: fixture.content.style,
        contexts: fixture.contexts.take(4).toList(),
        atomicRanges: [
          for (final atom in fixture.content.projection.atoms.take(2))
            (
              startUtf16: atom.displayStartUtf16,
              endUtf16: atom.displayEndUtf16,
            ),
        ],
      );
      expect(
        () => ForumBodyInlinePageContent(
          content: subset,
          dimensions: fixture.input.dimensions.take(2).toList(),
          rubyGroups: fixture.input.rubyGroups.take(2).toList(),
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test(
    'invalid pair geometry and paragraph/inline kind mismatches fail in pure admission',
    () {
      final fixture = MixedPagePreparationFixture();
      addTearDown(fixture.close);
      final pair = fixture.input.rubyGroups.first;
      expect(
        () => ForumBodyRubyPairRequest(
          base: pair.base,
          annotation: pair.annotation,
          gap: double.nan,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => ForumBodyTextPageContent.paragraph(
          fixture.contexts.first,
        ).nativeHandleCountFor(fixture.snapshot.first.fragments.single),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(fixture.cache.entryCount, 0);
    },
  );
}
