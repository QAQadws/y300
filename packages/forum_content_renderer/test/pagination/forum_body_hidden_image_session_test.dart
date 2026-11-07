import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    color: Color(0xff123456),
  ),
  fontRevision: 'hidden-image',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource();
  @override
  String get cacheKey => 'visible';
}

final class _Fixture {
  _Fixture(
    String html, {
    double height = 80,
    int maxPages = 100,
    int? pageHandles,
    int? pageImages,
    bool captureFloats = false,
    ForumBodyTableExtent extent = ForumBodyTableExtent.bookPage,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'hidden-image',
      conversionIdentity: 'none',
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: _reader,
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: maxPages,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 10000,
        maxRuns: 1000,
        maxIssuedLeases: 16,
      ),
      layoutId: 'hidden-image',
      width: 100,
      height: height,
      maxNativeHandlesPerPage: pageHandles,
      maxImagesPerPage: pageImages,
      textScaler: textScaler,
      captureFloats: captureFloats,
      tableExtent: extent,
      inlineImageResolver: (identity, element, style) {
        expect(style.visibilityHidden, isFalse);
        return null;
      },
      imageResolver: (identity, element) {
        resolved.add(element.path);
        return ForumBodyImageInput(
          identity: identity,
          element: element,
          entry: ForumHtmlReadableImageEntry(
            index: 0,
            url: element.resource!.rawSource!,
            rawSrc: element.resource!.rawSource!,
            resource: const _Resource(),
            htmlWidth: element.resource!.width,
            htmlHeight: element.resource!.height,
          ),
          layout: const ForumHtmlImageLayout(aspectRatio: 2),
        );
      },
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }

  late final ForumBodyDocument document;
  late final ForumBodyTextPageSession session;
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 24,
  );
  final resolved = <String>[];

  void finish() {
    for (var i = 0; !session.isComplete && i < 10000; i++) {
      final step = session.advance(
        maxEvents: 1,
        maxLines: 1,
        maxFormatParts: 1,
      );
      expect(step.pagesPublished, lessThanOrEqualTo(1));
      expect(step.madeProgress, isTrue);
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady && i < 10000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      return job.takeFragments();
    } finally {
      job.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a visible list marker survives a hidden-only block image item', () {
    final f = _Fixture(
      '<ol style="margin:0;padding-left:25px"><li>'
      '<img src="hidden" width="100" height="50" '
      'style="display:block;visibility:hidden"></li></ol>',
    )..finish();
    final fragments = f.session.snapshot.expand((page) => page.fragments);
    expect(fragments.where((part) => part.listMarker != null), hasLength(1));
    expect(f.resolved, isEmpty);
    final delivered = f.prepare(0).single as ForumBodyPreparedListItemFragment;
    expect(delivered.body, isA<ForumBodyPreparedHiddenImageFragment>());
    expect(delivered.projection.text, isEmpty);
    expect(delivered.glyphBoxes(0, 0), isEmpty);
    expect(delivered.imageCount, 0);
    expect(delivered.hasRenderedImages, isTrue);
    delivered.close();
    expect(f.session.activeIssuedImages, 0);
    expect(f.cache.activeLeases, 0);
  });

  test('hidden-only list items charge marker handles but no image slots', () {
    const body =
        '<ol style="margin:0;padding-left:25px">'
        '<li><img src="hidden" width="100" height="10" '
        'style="display:block;visibility:hidden"></li>'
        '<li><img src="hidden" width="100" height="10" '
        'style="display:block;visibility:hidden"></li></ol>';
    final images = _Fixture(body, pageImages: 1)..finish();
    expect(images.session.snapshot, hasLength(1));
    expect(images.session.snapshot.single.fragments, hasLength(2));
    expect(
      images.session.snapshot.single.fragments.every(
        (part) => part.imageCount == 0,
      ),
      isTrue,
    );
    final handles = _Fixture(body, pageHandles: 3)..finish();
    expect(handles.session.snapshot, hasLength(2));
    for (var page = 0; page < 2; page++) {
      final parts = handles.prepare(page);
      expect(parts, hasLength(1));
      parts.single.close();
    }
    expect(handles.resolved, isEmpty);
    expect(handles.cache.activeLeases, 0);
  });

  test('hidden marker metadata cannot bypass the retained-input limit', () {
    final f = _Fixture(
      '<ol><li><img src="hidden" alt="${'a' * 10000}" '
      'style="display:block;visibility:hidden"></li></ol>',
    );
    expect(
      f.finish,
      throwsA(
        isA<ForumBodyTextPageSessionException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTextPageSessionFailure.textLimit,
        ),
      ),
    );
    expect(f.resolved, isEmpty);
    expect(f.cache.activeLeases, 0);
  });

  testWidgets(
    'a hidden-only list paints its marker without a Host or source hit',
    (tester) async {
      final f = _Fixture(
        '<ol style="margin:0;padding-left:25px"><li>'
        '<img src="hidden" width="100" height="50" '
        'style="display:block;visibility:hidden"></li></ol>',
      )..finish();
      final parts = f.prepare(0);
      const key = ValueKey('hidden-list-pixels');
      var sourceHits = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              height: 80,
              child: RepaintBoundary(
                key: key,
                child: ForumBodyTextPageSurface.prepared(
                  snapshot: f.session.snapshot,
                  pageIndex: 0,
                  layoutId: 'hidden-image',
                  fragments: parts,
                  onSourceTap: (_, _) => sourceHits++,
                ),
              ),
            ),
          ),
        ),
      );
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await render.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var ink = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (bytes.getUint8((y * image.width + x) * 4 + 3) == 0) continue;
              ink++;
              expect(x, lessThan(25));
            }
          }
          expect(ink, greaterThan(0));
        } finally {
          image.dispose();
        }
      });
      await tester.tapAt(const Offset(40, 10));
      expect(sourceHits, 0);
      expect(f.resolved, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.session.activeIssuedFragments, 0);
      expect(f.cache.activeLeases, 0);
    },
  );

  test('scrolling keeps a tall invisible block in one natural slice', () {
    final f = _Fixture(
      '<p style="margin:0">A</p>'
      '<img src="hidden" width="100" height="400" '
      'style="display:block;visibility:hidden">'
      '<p style="margin:0">B</p>',
      height: 30,
      extent: ForumBodyTableExtent.natural,
    )..finish();
    expect(f.session.snapshot.map((page) => page.usedHeight), [10, 400, 10]);
    expect(f.session.snapshot[1].fragments, isEmpty);
    expect(f.prepare(1), isEmpty);
    expect(f.resolved, isEmpty);
  });

  test('invisible block images keep atomic geometry without resources', () {
    String body(String visibility) =>
        '<p style="margin:0">${'A' * 40}</p>'
        '<div style="$visibility"><img src="hidden" width="100" height="50">'
        '</div><p style="margin:0">B</p>';
    final visible = _Fixture(body(''))..finish();
    final hidden = _Fixture(body('visibility:hidden'))..finish();
    expect(hidden.resolved, isEmpty);
    expect(visible.resolved, hasLength(1));
    expect(
      hidden.session.snapshot.map((page) => page.usedHeight),
      visible.session.snapshot.map((page) => page.usedHeight),
    );
    expect(hidden.session.snapshot, hasLength(2));
    expect(hidden.session.snapshot[0].usedHeight, 40);
    final parts = hidden.prepare(1);
    expect(parts, hasLength(1));
    expect(parts.single.projection.text, 'B');
    expect(hidden.session.snapshot[1].fragments.single.top, 50);
    expect(parts.single.imageCount, 0);
    for (final part in parts) {
      part.close();
    }
    expect(hidden.session.activeIssuedImages, 0);
    expect(hidden.cache.activeLeases, 0);
  });

  test('image-only invisible pages preserve extent and stay resource free', () {
    final f = _Fixture(
      '<img src="hidden" width="100" height="50" '
      'style="display:block;visibility:hidden">',
      height: 30,
    )..finish();
    expect(f.session.snapshot.single.usedHeight, 30);
    expect(f.session.snapshot.single.fragments, isEmpty);
    expect(f.prepare(0), isEmpty);
    expect(f.resolved, isEmpty);
    expect(f.cache.layoutBuildCount, 0);
    expect(f.session.activeIssuedImages, 0);
  });

  test(
    'invisible inline slots retain author size, wrap and source positions',
    () {
      final f = _Fixture(
        '<p style="margin:0">AB'
        '<img src="hidden" width="40" height="20" alt="unread" '
        'style="display:inline-block;visibility:hidden">C DEFGH</p>',
      )..finish();
      final parts = f.prepare(0);
      final part = parts.single as ForumBodyPreparedInlineFragment;
      expect(part.projection.text, 'ABC DEFGH');
      expect(part.view.images, isEmpty);
      expect(part.imageCount, 0);
      expect(f.session.snapshot.single.fragments.single.imagePaths, isEmpty);
      expect(f.session.snapshot.single.usedHeight, 32);
      final before = part.glyphBoxes(1, 2).single;
      final after = part.glyphBoxes(2, 3).single;
      expect(after.left - before.right, 40);
      expect(part.glyphBoxes(6, 7).single.top, greaterThan(after.top));
      expect(part.hasRenderedImages, isTrue);
      expect(f.resolved, isEmpty);
      part.close();
      expect(f.cache.activeLeases, 0);
      expect(f.session.activeIssuedImages, 0);
    },
  );

  test('invisible inline CSS sizing uses the scaled fallback only once', () {
    final f = _Fixture(
      '<p style="margin:0">A'
      '<img src="hidden" style="display:inline;width:50%;height:15px;'
      'visibility:hidden">B</p>',
      textScaler: const TextScaler.linear(2),
    )..finish();
    final part = f.prepare(0).single as ForumBodyPreparedInlineFragment;
    final input = part.view.content.images.values.single;
    expect(input.isHidden, isTrue);
    expect(input.dimensions.size, const Size(50, 15));
    expect(part.glyphBoxes(1, 2).single.left, 70);
    expect(part.view.images, isEmpty);
    part.close();
  });

  test('an invisible float keeps text exclusion without image coverage', () {
    final f = _Fixture(
      '<img src="hidden" width="40" height="20" '
      'style="float:left;visibility:hidden">ABCDEFGH',
      captureFloats: true,
    )..finish();
    final parts = f.prepare(0);
    final text = parts.where((part) => part.projection.text.isNotEmpty).single;
    expect(text.projection.text, 'ABCDEFGH');
    final textBox = f.session.snapshot.single.fragments.singleWhere(
      (part) => part.kind == ForumBodyTextPageFragmentKind.paragraph,
    );
    expect(textBox.left + text.glyphBoxes(0, 1).single.left, 40);
    expect(parts.every((part) => part.imageCount == 0), isTrue);
    expect(f.resolved, isEmpty);
    for (final part in parts) {
      part.close();
    }
    expect(f.cache.activeLeases, 0);
    expect(f.session.activeIssuedImages, 0);
  });

  test(
    'invisible physical pages remain bounded by the session page budget',
    () {
      final f = _Fixture(
        List.filled(
          3,
          '<img src="hidden" style="display:block;visibility:hidden">',
        ).join(),
        height: 30,
        maxPages: 2,
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageFailure.pageLimit,
          ),
        ),
      );
      expect(f.resolved, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );
}
