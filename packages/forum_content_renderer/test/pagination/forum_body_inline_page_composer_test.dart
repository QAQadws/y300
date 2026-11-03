import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

void consume(ForumBodyTextPageComposer composer) {
  for (var work = 0; work < 100 && !composer.needsInput; work++) {
    final step = composer.advance(maxLines: 1);
    expect(step.linesInspected, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
  }
  expect(composer.needsInput, isTrue);
}

ForumBodyTextPageComposer composer(
  ForumBodyIdentity identity, {
  double width = 60,
  double height = 30,
}) {
  final result = ForumBodyTextPageComposer(
    identity: identity,
    layoutId: 'mixed-layout',
    width: width,
    height: height,
    maxPages: 100,
    maxFragments: 100,
  );
  addTearDown(result.close);
  return result;
}

void appendInline(
  ForumBodyTextPageComposer target,
  ForumBodyInlineParagraphLease lease, {
  int index = 0,
  double left = 0,
  double spaceBefore = 0,
}) => target.appendInline(
  lease: lease,
  paragraphIndex: index,
  left: left,
  spaceBefore: spaceBefore,
  spaceAtPageStart: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final height in [30.0, 100.0]) {
    test(
      'moved source windows keep actual page envelopes at height $height',
      () {
        final input = mixedInlineInput(base: 'AB ', suffix: '');
        final base = input.base.displayWindow(startUtf16: 0, endUtf16: 2);
        final space = input.base.displayWindow(startUtf16: 2, endUtf16: 3);
        final content = ForumBodyInlineSpanContent.compose(
          identity: input.content.identity,
          path: input.content.path,
          fontRevision: input.content.fontRevision,
          styleRevision: input.content.styleRevision,
          style: input.content.style,
          contexts: [
            input.contexts.first,
            base,
            input.annotation,
            space,
            input.contexts.last,
          ],
          sourceOrder: [0, 1, 3, 2, 4],
          atomicRanges: [(startUtf16: 1, endUtf16: 5)],
        );
        final cache = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final child = ForumBodyRubyGroupLayout.create(
          cache: cache,
          base: base,
          annotation: input.annotation,
        );
        addTearDown(child.close);
        final target = composer(content.identity, width: 40, height: height);
        appendInline(
          target,
          cache.acquireInline(
            content: content,
            width: 40,
            dimensions: [child.placeholderDimensions],
          ),
        );
        consume(target);
        target.finish();
        expect(content.projection.display.text, 'XABxy ');
        // The last displayed space belongs before RT in source. Its endpoint
        // alone would lose the annotation and its hidden RP source gap.
        expect(
          content.projection.display
              .sourceAtUtf16(6, affinity: HtmlProjectionAffinity.upstream)
              .sourceRune,
          4,
        );
        if (height == 30) {
          expect(target.snapshot, hasLength(2));
          expect(target.snapshot.first.fragments.single.sourceHint, (
            runeStart: 0,
            runeEnd: 1,
          ));
          expect(target.snapshot.last.fragments.single.sourceHint, (
            runeStart: 1,
            runeEnd: 7,
          ));
        } else {
          expect(target.snapshot, hasLength(1));
          final fragment = target.snapshot.single.fragments.single;
          expect((fragment.startLine, fragment.endLine), (0, 2));
          expect(fragment.sourceHint, (runeStart: 0, runeEnd: 7));
        }
        child.close();
        expect(cache.activeLeases, 0);
      },
    );
  }

  test(
    'existing composer paginates mixed lines using display coverage and raw source hints',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final lease = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [child.placeholderDimensions],
      );
      final target = composer(input.content.identity);
      appendInline(target, lease);
      final firstStep = target.advance(maxLines: 1);
      expect(firstStep.pagesPublished, 1);
      final prefix = target.snapshot;
      expect(prefix.length, 1);
      expect(prefix.isComplete, isFalse);
      final first = prefix.single.fragments.single;
      expect(first.kind, ForumBodyTextPageFragmentKind.inline);
      expect((first.coverageStartUtf16, first.coverageEndUtf16), (0, 5));
      expect(first.sourceHint, (runeStart: 0, runeEnd: 6));
      expect(first.height, 30);
      consume(target);
      target.finish();
      final last = target.snapshot.last.fragments.single;
      expect(target.snapshot.length, 2);
      expect((last.coverageStartUtf16, last.coverageEndUtf16), (5, 6));
      expect(last.sourceHint, (runeStart: 7, runeEnd: 8));
      expect(last.height, 20);
      expect(prefix.length, 1);
      expect(prefix.isComplete, isFalse);
      expect(prefix.single.fragments.single, same(first));
      expect(lease.isActive, isFalse);
      expect(child.isActive, isTrue);
      expect(
        target.snapshot.composerRevision,
        ForumBodyTextPageComposer.revision,
      );
    },
  );

  test(
    'ordinary and mixed inputs share ordering, signed spacing and continuation pages',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final target = composer(input.content.identity, height: 40);
      target.append(
        lease: cache.acquire(content: input.contexts.first, width: 60),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      consume(target);
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      appendInline(
        target,
        cache.acquireInline(
          content: input.content,
          width: 60,
          dimensions: [child.placeholderDimensions],
        ),
        index: 1,
        spaceBefore: -10,
      );
      consume(target);
      target.finish();
      expect(target.snapshot.length, 2);
      expect(target.snapshot.first.fragments.map((item) => item.kind), [
        ForumBodyTextPageFragmentKind.paragraph,
        ForumBodyTextPageFragmentKind.inline,
      ]);
      expect(target.snapshot.first.fragments.map((item) => item.top), [0, 10]);
      final continuation = target.snapshot.last.fragments.single;
      expect(continuation.paragraphIndex, 1);
      expect(continuation.top, 0);
      expect(continuation.startLine, 1);
      expect(target.nextParagraphIndex, 2);
    },
  );

  test(
    'oversized ruby row fails explicitly and preserves the already sealed prefix',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final target = composer(input.content.identity, height: 20);
      target.append(
        lease: cache.acquire(content: input.contexts.first, width: 60),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      consume(target);
      final prefix = target.snapshot;
      expect(prefix.length, 1);
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final lease = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [child.placeholderDimensions],
      );
      appendInline(target, lease, index: 1);
      expect(
        () => target.advance(maxLines: 1),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageFailure.oversizedGroup,
          ),
        ),
      );
      expect(target.isClosed, isTrue);
      expect(lease.isActive, isFalse);
      expect(child.isActive, isTrue);
      expect(target.snapshot.length, 1);
      expect(target.snapshot.first, same(prefix.first));
    },
  );

  test('owner retirement after one mixed page prevents late composition', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final input = mixedInlineInput();
    final target = composer(input.content.identity);
    final child = ForumBodyRubyGroupLayout.create(
      cache: cache,
      base: input.base,
      annotation: input.annotation,
    );
    addTearDown(child.close);
    final lease = cache.acquireInline(
      content: input.content,
      width: 60,
      dimensions: [child.placeholderDimensions],
    );
    appendInline(target, lease);
    target.advance(maxLines: 1);
    final prefix = target.snapshot;
    cache.close();
    expect(() => target.advance(maxLines: 1), throwsStateError);
    expect(target.snapshot.length, 1);
    expect(prefix.length, 1);
    expect(target.isClosed, isTrue);
    expect(cache.activeLeases, 0);
  });

  test(
    'rejected placement retains the input lease for a corrected request',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput();
      final target = composer(input.content.identity);
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final lease = cache.acquireInline(
        content: input.content,
        width: 60,
        dimensions: [child.placeholderDimensions],
      );
      expect(() => appendInline(target, lease, left: 1), throwsArgumentError);
      expect(lease.isActive, isTrue);
      expect(target.needsInput, isTrue);
      appendInline(target, lease);
      consume(target);
      target.finish();
      expect(target.snapshot.length, 2);
      expect(lease.isActive, isFalse);
    },
  );

  test(
    'ordinary readiness gate rejects an inline fragment even with identical glyph geometry',
    () {
      final document = const ForumBodyParser().parse(
        html: '<p>AB</p>',
        sourceId: 'kind-gate',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'loaded',
          linkColor: const Color(0xff0000ff),
        ),
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0',
      );
      final mixed = ForumBodyInlineSpanContent.compose(
        identity: document.identity,
        path: '0',
        fontRevision: content.fontRevision,
        styleRevision: content.styleRevision,
        style: content.style,
        contexts: [content],
        atomicRanges: [],
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final target = composer(document.identity);
      appendInline(
        target,
        cache.acquireInline(content: mixed, width: 60, dimensions: []),
      );
      consume(target);
      target.finish();
      final plain = cache.acquire(content: content, width: 60);
      addTearDown(plain.release);
      final fragment = target.snapshot.single.fragments.single;
      expect(plain.layout.height, fragment.height);
      expect(plain.layout.width, fragment.width);
      expect(
        () => validateForumBodyTextPageBinding(
          snapshot: target.snapshot,
          pageIndex: 0,
          layoutId: target.layoutId,
          leases: [plain],
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.identity,
          ),
        ),
      );
      expect(plain.isActive, isTrue);
    },
  );

  test(
    'emoji base and annotation remain one indivisible display atom across pages',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = mixedInlineInput(
        base: '👨‍👩‍👧‍👦e\u0301',
        annotation: 'xy',
      );
      final child = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(child.close);
      final width = child.size.width + 20;
      final target = composer(
        input.content.identity,
        width: width,
        height: child.size.height,
      );
      appendInline(
        target,
        cache.acquireInline(
          content: input.content,
          width: width,
          dimensions: [child.placeholderDimensions],
        ),
      );
      consume(target);
      target.finish();
      final atom = input.content.projection.atoms.single;
      expect(target.snapshot.length, 2);
      final first = target.snapshot.first.fragments.single;
      expect(first.coverageEndUtf16, atom.displayEndUtf16);
      final second = target.snapshot.last.fragments.single;
      expect(second.coverageStartUtf16, atom.displayEndUtf16);
      expect(first.sourceHint!.runeEnd, greaterThan(0));
    },
  );
}
