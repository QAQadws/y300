import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

void consume(ForumBodyTextPageComposer composer) {
  for (var work = 0; work < 100 && !composer.needsInput; work++) {
    composer.advance(maxLines: 1);
  }
  expect(composer.needsInput, isTrue);
}

final class RubyPage {
  RubyPage() {
    final input = mixedInlineInput();
    final band = ForumBodyTextBandContent(
      contexts: [input.base, input.annotation],
    );
    final prep = ForumBodyRubyGroupPreparation.fromRequests(
      cache: cache,
      base: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
      annotation: ForumBodyTextRequest.bandChild(band: band, childIndex: 1),
      ensureOwner: () {},
    );
    late ForumBodyRubyGroupLayout child;
    try {
      while (!prep.isReady) {
        prep.advance();
      }
      child = prep.takeLayout();
    } finally {
      prep.close();
    }
    final dimensions = [child.placeholderDimensions];
    final composer = ForumBodyTextPageComposer(
      identity: input.content.identity,
      layoutId: 'prepared-ruby-page',
      width: 60,
      height: 30,
      maxPages: 10,
      maxFragments: 10,
    );
    try {
      composer.appendInline(
        lease: cache.acquireInline(
          content: input.content,
          width: 60,
          dimensions: dimensions,
        ),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
      );
      consume(composer);
      composer.finish();
      snapshot = composer.snapshot;
    } finally {
      composer.close();
    }
    view = ForumBodyInlineParagraphView.adopt(
      cache: cache,
      parent: cache.tryAcquireInlineCached(
        content: input.content,
        width: 60,
        dimensions: dimensions,
      )!,
      startLine: 0,
      endLine: 1,
      rubyGroups: {0: child},
    );
    binding = ForumBodyPreparedTextFragment.inline(view);
    annotationSource = input.annotation.projection.sourceAtUtf16(0).sourceRune;
  }
  final cache = ForumBodyParagraphCache(
    maxEntries: 2,
    maxEstimatedBytes: 1 << 20,
  );
  late final ForumBodyTextPageSnapshot snapshot;
  late final ForumBodyInlineParagraphView view;
  late final ForumBodyPreparedTextFragment binding;
  late final int annotationSource;
  void close() {
    binding.close();
    cache.close();
  }

  Widget surface({
    void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
    onTap,
  }) => ForumBodyTextPageSurface.prepared(
    snapshot: snapshot,
    pageIndex: 0,
    layoutId: snapshot.layoutId,
    fragments: [binding],
    onSourceTap: onTap,
  );
}

final class PlainPages {
  PlainPages({this.secondOwner = false, this.inlineSecond = false}) {
    final doc = const ForumBodyParser().parse(
      html: '<p>A</p><p>B</p>',
      sourceId: 'typed-page',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'loaded',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final contents = [
      for (final path in ['0', '1'])
        const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: styles,
          path: path,
        ),
    ];
    final composer = ForumBodyTextPageComposer(
      identity: doc.identity,
      layoutId: 'typed-plain-page',
      width: 60,
      height: 40,
      maxPages: 10,
      maxFragments: 10,
    );
    try {
      for (var i = 0; i < 2; i++) {
        final owner = i == 1 && secondOwner ? other : cache;
        if (i == 1 && inlineSecond) {
          final mixed = ForumBodyInlineSpanContent.compose(
            identity: doc.identity,
            path: '1',
            fontRevision: contents[i].fontRevision,
            styleRevision: contents[i].styleRevision,
            style: contents[i].style,
            contexts: [contents[i]],
            atomicRanges: [],
          );
          final lease = owner.acquireInline(
            content: mixed,
            width: 60,
            dimensions: [],
          );
          final visible = owner.tryAcquireInlineCached(
            content: mixed,
            width: 60,
            dimensions: [],
          )!;
          composer.appendInline(
            lease: lease,
            paragraphIndex: i,
            left: 0,
            spaceBefore: 0,
            spaceAtPageStart: 0,
          );
          consume(composer);
          bindings.add(
            ForumBodyPreparedTextFragment.inline(
              ForumBodyInlineParagraphView.adopt(
                cache: owner,
                parent: visible,
                startLine: 0,
                endLine: 1,
                rubyGroups: {},
              ),
            ),
          );
        } else {
          final lease = owner.acquire(content: contents[i], width: 60);
          final visible = owner.tryAcquireCached(
            content: contents[i],
            width: 60,
          )!;
          composer.append(
            lease: lease,
            paragraphIndex: i,
            left: 0,
            spaceBefore: 0,
            spaceAtPageStart: 0,
          );
          consume(composer);
          bindings.add(
            ForumBodyPreparedTextFragment.paragraph(
              lease: visible,
              startLine: 0,
              endLine: 1,
            ),
          );
        }
      }
      composer.finish();
      snapshot = composer.snapshot;
    } finally {
      composer.close();
    }
  }
  final bool secondOwner;
  final bool inlineSecond;
  final cache = ForumBodyParagraphCache(
    maxEntries: 4,
    maxEstimatedBytes: 1 << 20,
  );
  final other = ForumBodyParagraphCache(
    maxEntries: 4,
    maxEstimatedBytes: 1 << 20,
  );
  final bindings = <ForumBodyPreparedTextFragment>[];
  late final ForumBodyTextPageSnapshot snapshot;
  void close() {
    for (final binding in bindings) {
      binding.close();
    }
    cache.close();
    other.close();
  }
}

Widget host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'existing PageSurface mounts complete ruby and taps actual child coordinates without native work',
    (tester) async {
      final input = RubyPage();
      addTearDown(input.close);
      final layouts = input.cache.layoutBuildCount;
      final pictures = input.cache.pictureBuildCount;
      final hits = <(ForumBodyTextPageFragment, int, int)>[];
      await tester.pumpWidget(
        host(
          input.surface(
            onTap: (fragment, position) => hits.add((
              fragment,
              position.sourceRune,
              position.displayUtf16,
            )),
          ),
        ),
      );
      expect(find.byType(ForumBodyInlineParagraphSurface), findsOneWidget);
      expect(find.byType(ForumBodyParagraphSurface), findsNothing);
      expect(input.binding.nativeLeases.length, 3);
      final box = input.view.selectionBoxes(3, 4).single;
      await tester.tapAt(
        tester.getTopLeft(find.byType(ForumBodyInlineParagraphSurface)) +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hits, [
        (input.snapshot.first.fragments.single, input.annotationSource, 3),
      ]);
      expect(input.cache.layoutBuildCount, layouts);
      expect(input.cache.pictureBuildCount, pictures);
      await tester.pumpWidget(const SizedBox());
      expect(input.binding.isActive, isFalse);
      expect(input.cache.activeLeases, 0);
      expect(input.binding.nativeLeases, isEmpty);
    },
  );

  testWidgets(
    'new fragment wrappers on rebuild keep the original mounted handles alive and current callbacks',
    (tester) async {
      final input = RubyPage();
      addTearDown(input.close);
      var taps = 0;
      await tester.pumpWidget(host(input.surface(onTap: (_, _) => taps++)));
      final gesture = await tester.startGesture(const Offset(30.1, 5));
      await tester.pumpWidget(
        host(
          ForumBodyTextPageSurface.prepared(
            snapshot: input.snapshot,
            pageIndex: 0,
            layoutId: input.snapshot.layoutId,
            fragments: [ForumBodyPreparedTextFragment.inline(input.view)],
            onSourceTap: (_, _) => taps += 10,
          ),
        ),
      );
      expect(input.view.isActive, isTrue);
      expect(input.cache.activeLeases, 3);
      await gesture.up();
      expect(taps, 10);
      await tester.pumpWidget(const SizedBox());
      expect(input.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'ordinary and inline fragments share the same actual page and placement',
    (tester) async {
      final input = PlainPages(inlineSecond: true);
      addTearDown(input.close);
      final hits = <int>[];
      await tester.pumpWidget(
        host(
          ForumBodyTextPageSurface.prepared(
            snapshot: input.snapshot,
            pageIndex: 0,
            layoutId: input.snapshot.layoutId,
            fragments: input.bindings,
            onSourceTap: (_, position) => hits.add(position.sourceRune),
          ),
        ),
      );
      expect(find.byType(ForumBodyParagraphSurface), findsOneWidget);
      expect(find.byType(ForumBodyInlineParagraphSurface), findsOneWidget);
      final ordinary = tester.getTopLeft(
        find.byType(ForumBodyParagraphSurface),
      );
      final inline = tester.getTopLeft(
        find.byType(ForumBodyInlineParagraphSurface),
      );
      expect(inline - ordinary, const Offset(0, 20));
      await tester.tapAt(ordinary + const Offset(.1, 10));
      await tester.tapAt(inline + const Offset(.1, 10));
      expect(hits, [0, 1]);
      await tester.pumpWidget(const SizedBox());
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'duplicate handles, cross-owner pages and mismatched line windows fail without consuming inputs',
    () {
      final input = PlainPages();
      addTearDown(input.close);
      final first = input.bindings.first as ForumBodyPreparedParagraphFragment;
      expect(
        () => validateForumBodyPreparedTextPageBinding(
          snapshot: input.snapshot,
          pageIndex: 0,
          layoutId: input.snapshot.layoutId,
          fragments: [first, first],
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.leases,
          ),
        ),
      );
      expect(first.isActive, isTrue);
      final foreign = PlainPages(secondOwner: true);
      addTearDown(foreign.close);
      expect(
        () => validateForumBodyPreparedTextPageBinding(
          snapshot: foreign.snapshot,
          pageIndex: 0,
          layoutId: foreign.snapshot.layoutId,
          fragments: foreign.bindings,
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.leases,
          ),
        ),
      );
      expect(foreign.bindings.every((binding) => binding.isActive), isTrue);
      final ruby = RubyPage();
      addTearDown(ruby.close);
      expect(
        () => validateForumBodyPreparedTextPageBinding(
          snapshot: ruby.snapshot,
          pageIndex: 1,
          layoutId: ruby.snapshot.layoutId,
          fragments: [ruby.binding],
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.geometry,
          ),
        ),
      );
      expect(ruby.binding.isActive, isTrue);
    },
  );

  test(
    'generation and kind validation borrow inputs, and invalid ordinary construction releases only its alias',
    () {
      final input = RubyPage();
      addTearDown(input.close);
      expect(() => input.surface(onTap: (_, _) {}), returnsNormally);
      expect(
        () => ForumBodyTextPageSurface.prepared(
          snapshot: input.snapshot,
          pageIndex: 0,
          layoutId: 'retired-generation',
          fragments: [input.binding],
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.generation,
          ),
        ),
      );
      expect(input.binding.isActive, isTrue);
      final plain = PlainPages();
      addTearDown(plain.close);
      final binding =
          plain.bindings.first as ForumBodyPreparedParagraphFragment;
      final alias = plain.cache.tryAcquireCached(
        content: binding.lease.content,
        width: 60,
      )!;
      expect(
        () => ForumBodyPreparedTextFragment.paragraph(
          lease: alias,
          startLine: 0,
          endLine: 2,
        ),
        throwsRangeError,
      );
      expect(alias.isActive, isFalse);
      expect(binding.isActive, isTrue);
      expect(
        () => validateForumBodyPreparedTextPageBinding(
          snapshot: plain.snapshot,
          pageIndex: 0,
          layoutId: plain.snapshot.layoutId,
          fragments: [input.binding, plain.bindings.last],
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(input.binding.isActive, isTrue);
    },
  );

  testWidgets(
    'owner close disables late mixed page paint and gesture before unmount',
    (tester) async {
      final input = RubyPage();
      addTearDown(input.close);
      var taps = 0;
      await tester.pumpWidget(host(input.surface(onTap: (_, _) => taps++)));
      final gesture = await tester.startGesture(const Offset(30.1, 5));
      input.cache.close();
      await gesture.up();
      expect(taps, 0);
      tester
          .renderObject<RenderBox>(find.byType(ForumBodyInlineParagraphSurface))
          .markNeedsPaint();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(input.cache.activeLeases, 0);
    },
  );
}
