import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 100,
  maxFragments: 100,
  maxParagraphs: 100,
  maxTextCodeUnits: 20000,
  maxRuns: 100,
  maxIssuedLeases: 16,
);

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

final class _Fixture {
  _Fixture(String html)
    : document = const ForumBodyParser().parse(
        html: html,
        sourceId: 'image-page',
        conversionIdentity: 'none',
      ) {
    addTearDown(cache.close);
  }
  final ForumBodyDocument document;
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 22,
  );
  final resolved = <ForumBodyElement>[];
  ForumBodyImageInput resolve(
    ForumBodyIdentity identity,
    ForumBodyElement element, {
    double ratio = 2,
    bool sticker = false,
  }) {
    final resource = element.resource!;
    final index = resolved.length;
    resolved.add(element);
    return ForumBodyImageInput(
      identity: identity,
      element: element,
      isSticker: sticker,
      layout: ForumHtmlImageLayout(aspectRatio: ratio),
      entry: ForumHtmlReadableImageEntry(
        index: index,
        url: resource.rawSource!,
        rawSrc: resource.rawSource!,
        resource: _Resource('image:$index'),
        htmlWidth: resource.width,
        htmlHeight: resource.height,
      ),
    );
  }

  ForumBodyTextPageSession session({
    ForumBodyImageResolver? resolver,
    bool missingResolver = false,
    double height = 100,
    String id = 'images-1',
    ForumBodyTextPageSessionLimits limits = _limits,
    int? maxNativeHandlesPerPage,
    int? maxNativeEntriesPerPage,
    int? maxNativeEstimatedBytesPerPage,
    ForumBodyTableExtent extent = ForumBodyTableExtent.bookPage,
  }) {
    final result = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: Colors.blue,
      ),
      cache: cache,
      limits: limits,
      layoutId: id,
      width: 100,
      height: height,
      imageResolver: missingResolver ? null : resolver ?? resolve,
      maxNativeHandlesPerPage: maxNativeHandlesPerPage,
      maxNativeEntriesPerPage: maxNativeEntriesPerPage,
      maxNativeEstimatedBytesPerPage: maxNativeEstimatedBytesPerPage,
      tableExtent: extent,
    );
    addTearDown(result.close);
    return result;
  }
}

void _finish(ForumBodyTextPageSession session, {int? pages}) {
  var calls = 0;
  while (!session.isComplete &&
      (pages == null || session.snapshot.length < pages)) {
    if (++calls > 10000) fail('Unbounded image pagination');
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
    expect(step.flowWorkDone, lessThanOrEqualTo(1));
    expect(step.paragraphsAdmitted, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.madeProgress, isTrue);
  }
}

List<ForumBodyPreparedTextFragment> _prepare(
  ForumBodyTextPageSession session,
  int page,
) {
  final job = session.openPagePreparation(page);
  var calls = 0;
  while (!job.isReady) {
    if (++calls > 1000) fail('Unbounded image preparation');
    final step = job.advance(maxFragments: 1, maxParts: 1);
    expect(step.fragmentsInspected, lessThanOrEqualTo(1));
    expect(step.partsInspected, lessThanOrEqualTo(1));
  }
  final result = job.takeFragments();
  job.close();
  return result;
}

Matcher _failure(ForumBodyTextPageSessionFailure failure) => throwsA(
  isA<ForumBodyTextPageSessionException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  test('text and repeated-URL images retain distinct real source order', () {
    final f = _Fixture(
      '<p style="text-indent:10px">AA<img src="https://x/a">BB'
      '<img src="https://x/a">CC</p>',
    );
    final s = f.session(height: 200);
    _finish(s);
    expect(s.snapshot, hasLength(1));
    final page = s.snapshot.single;
    expect(page.fragments.map((e) => e.paragraphIndex), [0, 1, 2, 3, 4]);
    expect(page.fragments.map((e) => e.kind), [
      ForumBodyTextPageFragmentKind.paragraph,
      ForumBodyTextPageFragmentKind.image,
      ForumBodyTextPageFragmentKind.paragraph,
      ForumBodyTextPageFragmentKind.image,
      ForumBodyTextPageFragmentKind.paragraph,
    ]);
    expect(f.resolved.map((e) => e.path), ['0/1', '0/3']);
    final prepared = _prepare(s, 0);
    expect(
      prepared.whereType<ForumBodyPreparedParagraphFragment>().map(
        (e) => e.projection.text,
      ),
      ['AA', 'BB', 'CC'],
    );
    final text = prepared
        .whereType<ForumBodyPreparedParagraphFragment>()
        .toList();
    expect(text[0].glyphBoxes(0, 1).single.left, 10);
    expect(text[1].glyphBoxes(0, 1).single.left, 0);
    expect(text[2].glyphBoxes(0, 1).single.left, 0);
    final images = prepared
        .whereType<ForumBodyPreparedImageFragment>()
        .toList();
    expect(images.map((e) => e.content.input.entry.index), [0, 1]);
    for (final image in images) {
      expect(image.projection.text, isEmpty);
      expect(image.runs, isEmpty);
      expect(image.lines, isEmpty);
      expect(image.nativeLeases, isEmpty);
      expect(image.glyphBoxes(0, 0), isEmpty);
    }
    for (final fragment in prepared) {
      fragment.close();
    }
  });

  test(
    'pure image pages are real fragments with zero shaping and fixed prefix',
    () {
      final f = _Fixture(List.filled(3, '<img src="https://x/a">').join());
      final s = f.session(height: 50);
      _finish(s, pages: 1);
      final prefix = s.snapshot;
      final first = prefix.single;
      _finish(s);
      expect(prefix, hasLength(1));
      expect(s.snapshot, hasLength(3));
      expect(s.snapshot.first, same(first));
      expect(f.cache.layoutBuildCount, 0);
      expect(f.cache.pictureBuildCount, 0);
      expect(f.cache.activeLeases, 0);
      for (var page = 0; page < 3; page++) {
        final job = s.openPagePreparation(page);
        expect(s.reservedViewFragments, 1);
        final probe = job.advance(maxFragments: 1, maxParts: 1);
        expect(probe.fragmentsInspected, 1);
        expect(probe.partsInspected, 1);
        expect(probe.layoutsBuilt, 0);
        expect(job.isReady, isFalse);
        job.advance(maxFragments: 1, maxParts: 1);
        final image =
            job.takeFragments().single as ForumBodyPreparedImageFragment;
        job.close();
        expect(image.isActive, isTrue);
        expect(s.reservedViewFragments, 0);
        expect(s.activeIssuedFragments, 1);
        expect(s.activeIssuedLeases, 0);
        expect(s.snapshot[page].fragments.single.sourceHint, isNull);
        expect(
          forumBodyTextSelectionAt(
            binding: image,
            fragment: s.snapshot[page].fragments.single,
            pageSize: const Size(100, 50),
            point: const Offset(10, 10),
          ),
          isNull,
        );
        image.close();
      }
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  for (final dir in ['ltr', 'rtl']) {
    test(
      'tall block image fits one page proportionally with $dir alignment',
      () {
        final f = _Fixture('<p dir="$dir"><img src="https://x/tall"></p>');
        final s = f.session(
          resolver: (identity, node) => f.resolve(identity, node, ratio: .1),
        );
        _finish(s);
        final fragment = s.snapshot.single.fragments.single;
        expect(fragment.height, 100);
        expect(
          fragment.imageFrame!.imageRect,
          Rect.fromLTWH(dir == 'rtl' ? 90 : 0, 0, 10, 100),
        );
        expect(fragment.startLine, 0);
        expect(fragment.endLine, 0);
        expect(fragment.coverageEndUtf16, 0);
      },
    );
  }

  testWidgets(
    'flowing image keeps its full block height and releases offscreen',
    (tester) async {
      final fixture = _Fixture(
        '<p>before</p><div style="background-color:#ddeeff">'
        '<img src="https://x/tall"></div><p>after</p>',
      );
      final session = fixture.session(
        resolver: (identity, node) =>
            fixture.resolve(identity, node, ratio: .05),
        extent: ForumBodyTableExtent.natural,
      );
      _finish(session, pages: 1);
      final prefix = session.snapshot;
      _finish(session);
      final pages = session.snapshot;
      expect(prefix, hasLength(1));
      expect(pages, hasLength(3));
      expect(pages.first, same(prefix.first));
      final imagePage = pages[1];
      final image = imagePage.fragments.single;
      expect(image.imageFrame!.imageRect, const Rect.fromLTWH(0, 0, 100, 2000));
      expect(image.sourceHint, isNull);
      expect(imagePage.usedHeight, 2000);
      expect(imagePage.backgrounds.single.height, 2000);
      expect(pages.last.fragments.single.paragraphIndex, 2);

      final host = _Host();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final errors = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              height: 80,
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  ForumBodyFlowSliver(
                    session: session,
                    prefix: pages,
                    onFailure: (error, _) => errors.add(error),
                    buildSlice: (_, snapshot, index, fragments) =>
                        ForumBodyTextPageSurface.prepared(
                          snapshot: snapshot,
                          pageIndex: index,
                          layoutId: snapshot.layoutId,
                          fragments: fragments,
                          compactHeight: true,
                          imageHost: host,
                        ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = find.byType(ForumHtmlImageView);
      expect(view, findsOneWidget);
      expect(tester.getSize(view), const Size(100, 2000));
      final extent = pages.fold<double>(
        0,
        (sum, page) => sum + page.usedHeight,
      );
      expect(controller.position.maxScrollExtent, extent);
      controller.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(view, findsOneWidget);
      controller.jumpTo(pages.first.usedHeight + imagePage.usedHeight);
      await tester.pumpAndSettle();
      expect(view, findsNothing);
      expect(session.activeIssuedImages, 0);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'new dimensions create another layout, old published geometry stays fixed',
    () {
      final f = _Fixture('<img src="https://x/a">');
      final old = f.session();
      _finish(old);
      final prepared = _prepare(old, 0).single;
      final original = old.snapshot.single.fragments.single;
      final next = f.session(
        id: 'images-2',
        resolver: (identity, node) => f.resolve(identity, node, ratio: 4),
      );
      _finish(next);
      expect(next.resolvedNodeCount, old.resolvedNodeCount);
      expect(next.snapshot.single.fragments.single.height, 25);
      expect(original.height, 50);
      expect(prepared.isActive, isTrue);
      old.close();
      expect(prepared.isActive, isFalse);
      expect(next.isClosed, isFalse);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'foreign actual node is rejected even with equal document identity and URL',
    () {
      const html = '<img src="https://x/a">';
      final f = _Fixture(html), foreign = _Fixture(html);
      final s = f.session(
        resolver: (identity, node) => f.resolve(
          identity,
          foreign.document.nodes.single as ForumBodyElement,
        ),
      );
      expect(
        () => _finish(s),
        _failure(ForumBodyTextPageSessionFailure.imageResource),
      );
      expect(s.snapshot, isEmpty);
    },
  );

  for (final html in [
    '<img src="https://x/a">',
    '<li><img src="https://x/a"></li>',
  ]) {
    test('missing resources cannot disappear: $html', () {
      final f = _Fixture(html);
      final s = f.session(missingResolver: true);
      expect(
        () => _finish(s),
        _failure(ForumBodyTextPageSessionFailure.imageResource),
      );
      expect(s.state, ForumBodyTextPageSessionState.failed);
      expect(s.snapshot, isEmpty);
    });
  }

  for (final handleLimit in [3, 16]) {
    test(
      'an image-first marker travels with its block at handle limit $handleLimit',
      () {
        final f = _Fixture(
          '<p>intro</p><ol start="12"><li><img src="https://x/a"><p>tail</p></li></ol>',
        );
        final s = f.session(
          height: 200,
          resolver: (identity, node) => f.resolve(identity, node, ratio: 100),
          maxNativeHandlesPerPage: handleLimit,
        );
        _finish(s);
        final pages = s.snapshot;
        expect(pages, hasLength(handleLimit == 3 ? 3 : 1));
        expect(
          pages
              .expand((page) => page.fragments)
              .where((fragment) => fragment.listMarker != null),
          hasLength(1),
        );
        final index = handleLimit == 3 ? 1 : 0;
        final page = pages[index];
        final slot = page.fragments.indexWhere(
          (fragment) => fragment.kind == ForumBodyTextPageFragmentKind.image,
        );
        final fragment = page.fragments[slot];
        final marker = fragment.listMarker!;
        expect(fragment.imagePaths, ['1/0/0']);
        expect(fragment.sourceHint, isNull);
        expect(marker.bounds.top, 0);
        expect(marker.bounds.bottom, greaterThan(fragment.height));
        expect(fragment.left + marker.bounds.left, greaterThanOrEqualTo(0));
        if (handleLimit == 16) {
          expect(
            page.fragments[slot + 1].top,
            greaterThanOrEqualTo(fragment.top + marker.bounds.bottom),
          );
        }
        final job = s.openPagePreparation(index);
        expect(job.expectedImageCount, 1);
        expect(job.expectedNativeLeaseCount, handleLimit == 3 ? 3 : 5);
        expect(s.reservedViewImages, 1);
        job.close();
        expect(s.reservedViewLeases, 0);
        expect(s.reservedViewImages, 0);

        final delivery = _prepare(s, index);
        final decorated = delivery[slot] as ForumBodyPreparedListItemFragment;
        final image = decorated.body as ForumBodyPreparedImageFragment;
        expect(decorated.nativeLeases, [decorated.picture]);
        expect(decorated.projection.text, isEmpty);
        expect(decorated.lines, isEmpty);
        expect(decorated.hasRenderedImages, isFalse);
        image.reportDisplayFrame(true);
        expect(decorated.hasRenderedImages, isTrue);
        expect(image.content.input.element, same(f.resolved.single));
        for (final binding in delivery) {
          binding.close();
        }
        expect(s.activeIssuedImages, 0);
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test(
    'a decorated image charges the marker against each native page budget',
    () {
      for (final failure in [
        ForumBodyTextPageFailure.nativeHandleLimit,
        ForumBodyTextPageFailure.nativeEntryLimit,
        ForumBodyTextPageFailure.nativeByteLimit,
      ]) {
        final f = _Fixture('<ol><li><img src="https://x/a"></li></ol>');
        final s = f.session(
          maxNativeHandlesPerPage:
              failure == ForumBodyTextPageFailure.nativeHandleLimit ? 2 : null,
          maxNativeEntriesPerPage:
              failure == ForumBodyTextPageFailure.nativeEntryLimit ? 1 : null,
          maxNativeEstimatedBytesPerPage:
              failure == ForumBodyTextPageFailure.nativeByteLimit ? 1 : null,
        );
        expect(
          () => _finish(s),
          throwsA(
            isA<ForumBodyTextPageException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
        expect(s.snapshot, isEmpty);
        expect(f.cache.activeLeases, 0);
      }
    },
  );

  test('sticker cannot silently turn into a block image', () {
    final f = _Fixture('<img src="https://x/smiley">');
    final s = f.session(
      resolver: (identity, node) => f.resolve(identity, node, sticker: true),
    );
    expect(
      () => _finish(s),
      _failure(ForumBodyTextPageSessionFailure.imageStructure),
    );
  });

  test(
    'late image failure retains the readable published prefix and delivery',
    () {
      final f = _Fixture('<img src="https://x/a"><img src="https://x/b">');
      var count = 0;
      final s = f.session(
        height: 50,
        resolver: (identity, node) =>
            ++count == 1 ? f.resolve(identity, node) : null,
      );
      _finish(s, pages: 1);
      final prefix = s.snapshot;
      final prepared = _prepare(s, 0).single;
      expect(
        () => _finish(s),
        _failure(ForumBodyTextPageSessionFailure.imageResource),
      );
      expect(s.snapshot, same(prefix));
      expect(s.retainedParagraphCount, 1);
      expect(prepared.isActive, isTrue);
      prepared.close();
      expect(_prepare(s, 0).single.isActive, isTrue);
      s.close();
      expect(s.retainedTextCodeUnits, 0);
    },
  );

  test('zero-native delivered resources still consume issued capacity', () {
    final f = _Fixture('<img src="https://x/a">');
    final s = f.session(
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 2,
        maxFragments: 2,
        maxParagraphs: 2,
        maxTextCodeUnits: 100,
        maxRuns: 0,
        maxIssuedLeases: 1,
      ),
    );
    _finish(s);
    final job = s.openPagePreparation(0);
    expect(
      () => s.openPagePreparation(0),
      _failure(ForumBodyTextPageSessionFailure.leaseLimit),
    );
    job.close();
    final delivered = _prepare(s, 0).single;
    expect(
      () => s.openPagePreparation(0),
      _failure(ForumBodyTextPageSessionFailure.leaseLimit),
    );
    delivered.close();
    final next = _prepare(s, 0).single;
    f.cache.close();
    expect(next.isActive, isFalse);
    expect(s.isClosed, isTrue);
  });

  test(
    'resource metadata uses existing retained-input budget before publication',
    () {
      final f = _Fixture('<img src="https://x/a">');
      final s = f.session(
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 2,
          maxFragments: 2,
          maxParagraphs: 2,
          maxTextCodeUnits: 1,
          maxRuns: 0,
          maxIssuedLeases: 2,
        ),
      );
      expect(
        () => _finish(s),
        _failure(ForumBodyTextPageSessionFailure.textLimit),
      );
      expect(s.snapshot, isEmpty);
      expect(s.retainedTextCodeUnits, 0);
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  testWidgets(
    'native page mounts shared image view in its immutable image rectangle',
    (tester) async {
      final f = _Fixture('<img src="https://x/tall">');
      final s = f.session(
        resolver: (identity, node) => f.resolve(identity, node, ratio: .1),
      );
      _finish(s);
      final images = _prepare(s, 0);
      final host = _Host();
      final image = images.single as ForumBodyPreparedImageFragment;
      final resolvedLayouts = <ForumHtmlImageLayout>[];
      final taps = <ForumBodyPreparedImageFragment>[];
      expect(s.activeIssuedFragments, 1);
      expect(s.activeIssuedLeases, 0);
      expect(image.hasRenderedImage, isFalse);
      expect(
        () => ForumBodyTextPageSurface.prepared(
          snapshot: s.snapshot,
          pageIndex: 0,
          layoutId: s.snapshot.layoutId,
          fragments: images,
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: s.snapshot,
              pageIndex: 0,
              layoutId: s.snapshot.layoutId,
              fragments: images,
              imageHost: host,
              onImageTap: taps.add,
              onImageLayoutResolved: (binding, layout) {
                expect(binding, same(image));
                resolvedLayouts.add(layout);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ForumHtmlImageView), findsOneWidget);
      expect(
        tester.getSize(find.byType(ForumHtmlImageView)),
        const Size(10, 100),
      );
      expect(host.fit, BoxFit.contain);
      await tester.tapAt(
        tester.getTopLeft(find.byType(ForumBodyTextPageSurface)) +
            const Offset(50, 50),
      );
      expect(taps, isEmpty);
      await tester.tap(find.byType(ForumHtmlImageView));
      expect(taps.single, same(image));
      final retiredTap = tester
          .widget<GestureDetector>(
            find
                .ancestor(
                  of: find.byType(ForumHtmlImageView),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .onTap!;
      host.reportSize!(const Size(400, 100));
      expect(resolvedLayouts.single.aspectRatio, 4);
      expect(image.hasRenderedImage, isFalse);
      host.reportFrame!();
      expect(image.hasRenderedImage, isTrue);
      host.reportFailure!();
      expect(image.hasRenderedImage, isFalse);
      host.reportFrame!();
      await tester.pump();
      expect(
        tester.getSize(find.byType(ForumHtmlImageView)),
        const Size(10, 100),
      );
      expect(s.snapshot.single.fragments.single.height, 100);
      expect(f.cache.layoutBuildCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(images.single.isActive, isFalse);
      expect(image.hasRenderedImage, isFalse);
      expect(s.activeIssuedFragments, 0);
      retiredTap();
      expect(taps, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  test('resource Host cannot substitute another URL or cache binding', () {
    final f = _Fixture('<img src="https://x/tall">');
    final s = f.session();
    _finish(s);
    final fragments = _prepare(s, 0);
    for (final display in [
      const _DisplayImage(sourceUrl: 'https://x/other'),
      const _DisplayImage(cacheKey: 'other-cache'),
      const _DisplayImage(isSticker: true),
    ]) {
      expect(
        () => ForumBodyTextPageSurface.prepared(
          snapshot: s.snapshot,
          pageIndex: 0,
          layoutId: s.snapshot.layoutId,
          fragments: fragments,
          imageHost: _Host(display),
        ),
        throwsA(
          isA<ForumBodyTextPageSurfaceException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSurfaceFailure.identity,
          ),
        ),
      );
      expect(fragments.single.isActive, isTrue);
    }
    fragments.single.close();
  });

  test(
    'equal geometry from another generation does not bind the saved resource frame',
    () {
      final f = _Fixture('<img src="https://x/tall">');
      final a = f.session(), b = f.session();
      _finish(a);
      _finish(b);
      final foreign = _prepare(b, 0);
      expect(
        () => ForumBodyTextPageSurface.prepared(
          snapshot: a.snapshot,
          pageIndex: 0,
          layoutId: a.snapshot.layoutId,
          fragments: foreign,
          imageHost: _Host(),
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      foreign.single.close();
      expect(_prepare(a, 0).single.isActive, isTrue);
    },
  );

  test(
    'many zero-native images yield separately during whole-page preflight and cancellation',
    () {
      final f = _Fixture(List.filled(12, '<img src="https://x/a">').join());
      final s = f.session(
        resolver: (identity, node) => f.resolve(identity, node, ratio: 100),
      );
      _finish(s);
      expect(s.snapshot, hasLength(1));
      final job = s.openPagePreparation(0);
      for (var i = 0; i < 12; i++) {
        final step = job.advance(maxFragments: 1, maxParts: 1);
        expect(step.partsInspected, 1);
        expect(step.fragmentsInspected, 1);
        expect(job.preparedFragmentCount, 0);
      }
      final step = job.advance(maxFragments: 1, maxParts: 1);
      expect(step.fragmentsPrepared, 1);
      job.close();
      expect(s.pendingPreparationCount, 0);
      expect(s.activeIssuedLeases, 0);
      expect(s.reservedViewLeases, 0);
      expect(f.cache.layoutBuildCount, 0);
      expect(_prepare(s, 0), hasLength(12));
    },
  );

  for (final mixed in [false, true]) {
    test(
      'dense resource pages seal within actual delivery capacity: mixed=$mixed',
      () {
        final f = _Fixture(
          List.filled(
            7,
            mixed
                ? '<p>A</p><img src="https://x/a">'
                : '<img src="https://x/a">',
          ).join(),
        );
        final s = f.session(
          resolver: (identity, node) => f.resolve(identity, node, ratio: 100),
          limits: const ForumBodyTextPageSessionLimits(
            maxPages: 20,
            maxFragments: 100,
            maxParagraphs: 100,
            maxTextCodeUnits: 20000,
            maxRuns: 100,
            maxIssuedLeases: 3,
          ),
        );
        _finish(s);
        expect(s.snapshot.length, mixed ? 5 : 3);
        expect(s.snapshot.every((page) => page.fragments.length <= 3), isTrue);
        final paths = <String>[], text = StringBuffer();
        for (final page in s.snapshot) {
          expect(page.usedHeight, lessThan(100));
          final values = _prepare(s, page.index);
          for (final value in values) {
            if (value is ForumBodyPreparedImageFragment) {
              paths.add(value.content.input.element.path);
            } else {
              text.write(value.projection.text);
            }
            value.close();
          }
        }
        expect(paths.toSet(), hasLength(7));
        expect(text.toString(), mixed ? 'AAAAAAA' : '');
        expect(s.activeIssuedLeases, 0);
      },
    );
  }

  test(
    'Host page allotment retains current and neighbor resource pages without fake handles',
    () {
      final f = _Fixture(List.filled(7, '<img src="https://x/a">').join());
      final s = f.session(
        maxNativeHandlesPerPage: 3,
        resolver: (identity, node) => f.resolve(identity, node, ratio: 100),
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 20,
          maxFragments: 100,
          maxParagraphs: 100,
          maxTextCodeUnits: 20000,
          maxRuns: 0,
          maxIssuedLeases: 6,
        ),
      );
      _finish(s);
      expect(s.snapshot.map((p) => p.fragments.length), [3, 3, 1]);
      final current = _prepare(s, 0), neighbor = _prepare(s, 1);
      expect(s.activeIssuedLeases, 0);
      expect(f.cache.layoutBuildCount, 0);
      expect(
        () => s.openPagePreparation(2),
        _failure(ForumBodyTextPageSessionFailure.leaseLimit),
      );
      for (final value in current) {
        value.close();
      }
      final last = _prepare(s, 2);
      expect(neighbor.every((f) => f.isActive), isTrue);
      expect(last.single.isActive, isTrue);
    },
  );
}

final class _DisplayImage implements ForumHtmlDisplayImage {
  const _DisplayImage({
    this.sourceUrl = 'https://x/tall',
    this.cacheKey = 'image:0',
    this.isSticker = false,
  });
  @override
  final String sourceUrl;
  @override
  final String cacheKey;
  @override
  Object get identity => cacheKey;
  @override
  final bool isSticker;
  @override
  Size? get htmlSize => null;
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(aspectRatio: .1, isFallback: true);
}

final class _Host implements ForumHtmlImageHost {
  _Host([this.display = const _DisplayImage()]);
  final ForumHtmlDisplayImage display;
  BoxFit? fit;
  ValueChanged<Size>? reportSize;
  VoidCallback? reportFrame, reportFailure;
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => display;
  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;
  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}
  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) {
    this.fit = fit;
    reportSize = onImageResolved;
    reportFrame = onFirstFrameRendered;
    reportFailure = onImageFailed;
    return const ColoredBox(color: Colors.blue);
  }
}
