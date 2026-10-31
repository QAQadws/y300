import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

import '../inline/test_support/mixed_inline_fixture.dart';

void _consume(ForumBodyTextPageComposer composer) {
  for (var i = 0; !composer.needsInput && i < 100; i++) {
    final step = composer.advance(maxLines: 1);
    expect(step.linesInspected, lessThanOrEqualTo(1));
  }
  expect(composer.needsInput, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 22);
  });
  tearDown(() => cache.close());

  for (final suffix in ['Y<br>', 'Y\u2028', 'Y\u2029']) {
    test('mixed windows use the actual final empty row: $suffix', () {
      final input = mixedInlineInput(prefix: '', suffix: suffix);
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final parent = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: [child.placeholderDimensions],
      );
      addTearDown(parent.release);
      final layout = parent.layout;
      final display = input.content.projection.display.text;
      final engine = input.content.projection.engineText;
      expect(display.length, greaterThan(engine.length));
      expect(layout.lines, hasLength(2));
      expect(layout.lineWindow(ForumBodyParagraphWindow.full), (
        startLine: 0,
        endLine: 2,
      ));
      expect(
        layout.lineWindow(ForumBodyParagraphWindow.beforeTerminalEmptyLine),
        (startLine: 0, endLine: 1),
      );
      expect(layout.lineWindow(ForumBodyParagraphWindow.terminalEmptyLine), (
        startLine: 1,
        endLine: 2,
      ));
      final tail = layout.fragment(1, 2);
      expect(tail.coverageStartUtf16, display.length);
      expect(tail.coverageEndUtf16, display.length);
      expect(tail.engineCoverageStartUtf16, engine.length);
      expect(tail.engineCoverageEndUtf16, engine.length);
      expect(tail.atomIndices, isEmpty);
      // The native empty row inherits the preceding placeholder's line metrics.
      // Keep that actual frame rather than inventing a default-font row.
      expect(tail.height, 30);
      parent.release();
      expect(
        () => layout.lineWindow(ForumBodyParagraphWindow.full),
        returnsNormally,
      );
      cache.clearUnpinned();
      expect(
        () => layout.lineWindow(ForumBodyParagraphWindow.full),
        throwsStateError,
      );
    });
  }

  test(
    'annotation separators and soft wraps cannot manufacture a parent terminal row',
    () {
      for (final (annotation, suffix, width) in [
        ('xy<br>', '', 100.0),
        ('xy', 'ZZ', 40.0),
        ('xy', '', 100.0),
      ]) {
        final input = mixedInlineInput(
          prefix: '',
          annotation: annotation,
          suffix: suffix,
        );
        final parent = cache.acquireInline(
          content: input.content,
          width: width,
          dimensions: const [
            PlaceholderDimensions(
              size: Size(40, 30),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 25,
            ),
          ],
        );
        try {
          for (final window in [
            ForumBodyParagraphWindow.beforeTerminalEmptyLine,
            ForumBodyParagraphWindow.terminalEmptyLine,
          ]) {
            expect(
              () => parent.layout.lineWindow(window),
              throwsA(
                isA<ForumBodyParagraphLayoutException>().having(
                  (e) => e.failure,
                  'failure',
                  ForumBodyParagraphLayoutFailure.coverage,
                ),
              ),
            );
          }
        } finally {
          parent.release();
          cache.clearUnpinned();
        }
      }
    },
  );

  test(
    'composer splits a mixed terminal BR once and typed delivery pins no hidden ruby',
    () {
      final input = mixedInlineInput(prefix: '', suffix: 'Y<br>');
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      final dimensions = [child.placeholderDimensions];
      child.close();
      final composer = ForumBodyTextPageComposer(
        identity: input.content.identity,
        layoutId: 'mixed-terminal-windows',
        width: 100,
        height: 30,
        maxPages: 10,
        maxFragments: 10,
      );
      addTearDown(composer.close);
      for (final (index, window) in [
        (0, ForumBodyParagraphWindow.beforeTerminalEmptyLine),
        (1, ForumBodyParagraphWindow.terminalEmptyLine),
      ]) {
        composer.appendInline(
          lease: cache.acquireInline(
            content: input.content,
            width: 100,
            dimensions: dimensions,
          ),
          paragraphIndex: index,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
          window: window,
        );
        _consume(composer);
      }
      composer.finish();
      final snapshot = composer.snapshot;
      expect(snapshot, hasLength(2));
      expect(snapshot.first.fragments.single.height, 30);
      final tail = snapshot.last.fragments.single;
      expect((tail.startLine, tail.endLine), (1, 2));
      expect((tail.coverageStartUtf16, tail.coverageEndUtf16), (6, 6));
      expect(tail.sourceHint, isNull);
      final plan = ForumBodyInlinePageContent(
        content: input.content,
        dimensions: dimensions,
        rubyGroups: [
          ForumBodyRubyPairRequest(
            base: ForumBodyTextRequest.paragraph(input.base),
            annotation: ForumBodyTextRequest.paragraph(input.annotation),
          ),
        ],
      );
      expect(plan.nativeHandleCountFor(snapshot.first.fragments.single), 3);
      expect(plan.nativeHandleCountFor(tail), 1);
      final preparation = createForumBodyTextPagePreparation(
        cache: cache,
        snapshot: snapshot,
        pageIndex: 1,
        inputs: [plan],
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
        onTransfer: (_, _) {},
        onRetire: (_) {},
      );
      addTearDown(preparation.close);
      expect(preparation.tryPrepareCached(), isTrue);
      final fragment =
          preparation.takeFragments().single as ForumBodyPreparedInlineFragment;
      try {
        expect(fragment.nativeLeases, hasLength(1));
        expect(fragment.view.atomIndices, isEmpty);
        expect(
          fragment.view.selectionBoxes(
            0,
            input.content.projection.display.text.length,
          ),
          isEmpty,
        );
        final hit = fragment.view.sourceAt(const Offset(5, 5));
        expect(hit.displayUtf16, 6);
        expect(hit.isExact, isFalse);
        expect(cache.activeLeases, 1);
      } finally {
        fragment.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'rejected inline window leaves lease usable for a corrected request',
    () {
      final input = mixedInlineInput();
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final parent = cache.acquireInline(
        content: input.content,
        width: 100,
        dimensions: [child.placeholderDimensions],
      );
      addTearDown(parent.release);
      final composer = ForumBodyTextPageComposer(
        identity: input.content.identity,
        layoutId: 'invalid-terminal-window',
        width: 100,
        height: 40,
        maxPages: 10,
        maxFragments: 10,
      );
      addTearDown(composer.close);
      void append(ForumBodyParagraphWindow window) => composer.appendInline(
        lease: parent,
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        window: window,
      );
      expect(
        () => append(ForumBodyParagraphWindow.terminalEmptyLine),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(parent.isActive, isTrue);
      expect(composer.needsInput, isTrue);
      append(ForumBodyParagraphWindow.full);
      _consume(composer);
      composer.finish();
      expect(composer.snapshot, hasLength(1));
      expect(parent.isActive, isFalse);
    },
  );
}
