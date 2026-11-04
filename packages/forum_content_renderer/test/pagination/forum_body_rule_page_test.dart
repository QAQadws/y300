import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(
    String html, {
    double width = 100,
    double height = 100,
    int maxFragments = 100,
  }) {
    document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'rules',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 20);
    session = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 10,
          height: 1,
          color: Color(0xff123456),
        ),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
        paragraphAfter: 0,
      ),
      width: width,
      height: height,
      layoutId: 'rules-layout',
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: maxFragments,
        maxParagraphs: 100,
        maxTextCodeUnits: 10000,
        maxRuns: 1000,
        maxIssuedLeases: 64,
      ),
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }
  late final ForumBodyDocument document;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void finish() {
    for (var i = 0; !session.isComplete && i < 10000; i++) {
      final step = session.advance(maxEvents: 1, maxLines: 1);
      expect(step.madeProgress, isTrue);
      expect(step.pagesPublished, lessThanOrEqualTo(1));
    }
    expect(session.isComplete, isTrue);
  }
}

ForumBodyTextPageComposer _composer({
  double height = 10,
  int maxFragments = 100,
  int maxPages = 100,
}) {
  final composer = ForumBodyTextPageComposer(
    identity: const ForumBodyParser()
        .parse(html: '', sourceId: 'rules', conversionIdentity: 'none')
        .identity,
    layoutId: 'rules',
    width: 100,
    height: height,
    maxPages: maxPages,
    maxFragments: maxFragments,
  );
  addTearDown(composer.close);
  return composer;
}

void _rule(
  ForumBodyTextPageComposer composer, {
  double thickness = 1,
  double spaceBefore = 0,
}) => composer.appendRule(
  path: 'rule',
  left: 0,
  width: 100,
  thickness: thickness,
  color: const Color(0xff123456),
  spaceBefore: spaceBefore,
);

Matcher _failure(ForumBodyTextPageFailure failure) => throwsA(
  isA<ForumBodyTextPageException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real block flow resolves rule margins, width and color without fake text',
    () {
      final fixture = _Fixture(
        'a<hr class="l" style="width:50%;color:#c02030">b',
      );
      fixture.finish();
      final page = fixture.session.snapshot.single;
      expect(page.fragments.map((f) => f.top), [0, 21]);
      final rule = page.rules.single;
      expect(
        (rule.left, rule.top, rule.width, rule.thickness, rule.color),
        (25, 15, 50, 1, const Color(0xffc02030)),
      );
      expect(page.usedHeight, 31);
      expect(page.itemCount, 3);
      expect(fixture.cache.layoutBuildCount, 2);
      final delivery = fixture.session.preparePageFragments(0);
      try {
        expect(
          delivery.whereType<ForumBodyPreparedParagraphFragment>().map(
            (f) => f.lease.content.projection.text,
          ),
          ['a', 'b'],
        );
      } finally {
        for (final fragment in delivery) {
          fragment.close();
        }
      }
      expect(() => page.rules.clear(), throwsUnsupportedError);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a rule breaks once before an occupied edge and never splits or repeats',
    () {
      final fixture = _Fixture('a<hr class="l">b', height: 15);
      fixture.finish();
      final pages = fixture.session.snapshot;
      expect(pages.length, 3);
      expect(pages.map((p) => p.rules.length), [0, 1, 0]);
      expect(pages[1].rules.single.top, 0);
      expect(pages[1].usedHeight, 1);
      expect(pages[2].fragments.single.top, 0);
      expect(fixture.cache.layoutBuildCount, 2);
    },
  );

  test(
    'rule-only pages need no native entries, text or synthetic source hints',
    () {
      final fixture = _Fixture(
        List.filled(9, '<hr style="margin:0">').join(),
        height: 4,
      );
      fixture.finish();
      expect(fixture.session.snapshot.map((p) => p.rules.length), [4, 4, 1]);
      expect(fixture.session.retainedParagraphCount, 0);
      expect(fixture.session.retainedTextCodeUnits, 0);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.entryCount, 0);
      for (var page = 0; page < 3; page++) {
        expect(fixture.session.preparePageFragments(page), isEmpty);
        expect(fixture.session.snapshot[page].fragments, isEmpty);
      }
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );

  test(
    'visibility retains geometry, display none retains neither rule nor margin',
    () {
      final fixture = _Fixture(
        '<hr hidden><hr style="visibility:hidden;margin:0"><hr style="display:none">',
      );
      fixture.finish();
      final page = fixture.session.snapshot.single;
      expect(page.rules.length, 1);
      expect(page.rules.single.color.a, 0);
      expect(page.usedHeight, 1);
    },
  );

  test('rule padding and relative widths use the real nested containing box', () {
    final fixture = _Fixture(
      '<div style="padding:3px 10px"><hr style="width:50%;margin:2px auto;padding:4px 2px"></div>',
    );
    fixture.finish();
    final rule = fixture.session.snapshot.single.rules.single;
    expect((rule.left, rule.width, rule.top), (30, 40, 9));
    expect(fixture.session.snapshot.single.usedHeight, 19);
  });

  test(
    'rules share the fragment budget and preserve an already published prefix',
    () {
      final composer = _composer(height: 1, maxFragments: 1);
      _rule(composer);
      expect(composer.advanceRule(), (pagesPublished: 1, isComplete: true));
      final prefix = composer.snapshot;
      _rule(composer);
      expect(
        composer.advanceRule,
        _failure(ForumBodyTextPageFailure.fragmentLimit),
      );
      expect(composer.snapshot.single, same(prefix.single));
      expect(composer.retainedFragmentCount, 1);
      expect(composer.isClosed, isTrue);
    },
  );

  test(
    'a pending break is bounded and close drops only the unpublished rule',
    () {
      final composer = _composer(height: 2);
      _rule(composer);
      composer.advanceRule();
      _rule(composer, spaceBefore: 2);
      expect(composer.advanceRule(), (pagesPublished: 1, isComplete: false));
      expect(composer.hasPendingRule, isTrue);
      final prefix = composer.snapshot;
      composer.close();
      expect(composer.snapshot.single, same(prefix.single));
      expect(composer.retainedFragmentCount, 1);
      expect(() => composer.advanceRule(), throwsStateError);
    },
  );

  test(
    'oversized rules and page exhaustion fail without retrying a sealed prefix',
    () {
      final huge = _composer(height: 1);
      _rule(huge, thickness: 2);
      expect(
        huge.advanceRule,
        _failure(ForumBodyTextPageFailure.oversizedGroup),
      );
      expect(huge.snapshot, isEmpty);
      final full = _composer(height: 1, maxPages: 1);
      _rule(full);
      full.advanceRule();
      _rule(full);
      expect(full.advanceRule, _failure(ForumBodyTextPageFailure.pageLimit));
      expect(full.snapshot.length, 1);
      expect(full.retainedFragmentCount, 1);
    },
  );

  test('invalid numeric rule input never becomes pending', () {
    final composer = _composer();
    for (final thickness in [double.nan, double.infinity, 0.0, -1.0]) {
      expect(() => _rule(composer, thickness: thickness), throwsArgumentError);
      expect(composer.needsInput, isTrue);
    }
  });

  testWidgets(
    'the visible page paints the same clipped rule geometry with no text or tap target',
    (tester) async {
      final fixture = _Fixture(
        '<hr style="margin:3px 0 0 -5px;width:30px;color:#ff0000">',
        width: 20,
        height: 10,
      );
      fixture.finish();
      // First-node adjoining margin trims; horizontal overflow remains real and
      // is clipped at the final page rather than changing the declared width.
      final rule = fixture.session.snapshot.single.rules.single;
      expect((rule.left, rule.top, rule.width), (-5, 0, 30));
      final key = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: const Color(0xffffffff),
                child: ForumBodyTextPageSurface(
                  snapshot: fixture.session.snapshot,
                  pageIndex: 0,
                  layoutId: 'rules-layout',
                  leases: const [],
                  onSourceTap: (_, _) => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }))!;
      expect(pixels.length, 20 * 10 * 4);
      for (var x = 0; x < 20; x++) {
        expect(pixels.sublist(x * 4, x * 4 + 4), [255, 0, 0, 255]);
        final below = (20 + x) * 4;
        expect(pixels.sublist(below, below + 4), [255, 255, 255, 255]);
      }
      await tester.tapAt(const Offset(5, .5));
      expect(taps, 0);
      expect(find.byType(ForumBodyParagraphSurface), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
