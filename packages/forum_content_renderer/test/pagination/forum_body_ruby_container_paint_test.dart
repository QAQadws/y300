import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _column =
    '<rb style="font-size:20px;line-height:1">A</rb><rb style="font-size:20px;line-height:1">B</rb><rt style="font-size:10px;line-height:1">x</rt><rt style="font-size:10px;line-height:1">y</rt>';
const _segment =
    '<rb style="font-size:20px;line-height:1">A</rb><rb style="font-size:20px;line-height:1">B</rb><rtc style="font-size:10px;line-height:1"><rt>x</rt><rt>y</rt></rtc><rtc style="font-size:10px;line-height:1">word</rtc>';
const _space =
    '<rb style="font-size:20px;line-height:1">A</rb> <rb style="font-size:20px;line-height:1">B</rb><rt style="font-size:10px;line-height:1">x</rt> <rt style="font-size:10px;line-height:1">y</rt>';

final class _Fixture {
  _Fixture(
    String children, {
    TextDirection direction = TextDirection.ltr,
    bool under = false,
    double rootSize = 20,
    double width = 240,
    double height = 180,
    String before = '',
    Color ink = const Color(0x00000000),
    String rootBackground = 'rgba(255,0,0,.5)',
    ForumBodyStyleScope backgroundScope = ForumBodyStyleScope.asDefault,
    TextScaler scaler = TextScaler.noScaling,
  }) {
    final document = const ForumBodyParser().parse(
      html:
          '$before<p dir="${direction.name}" style="margin:0"><ruby style="font-size:${rootSize}px;line-height:1;ruby-position:${under ? 'under' : 'over'};background:$rootBackground">$children</ruby></p>',
      sourceId: 'root-paint',
      conversionIdentity: 'none',
    );
    session = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          height: 1,
          color: ink,
        ),
        fontRevision: 'ahem',
        linkColor: const Color(0x00000000),
        paragraphAfter: 0,
        textDirection: direction,
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.background: backgroundScope,
        }),
      ),
      cache: cache,
      width: width,
      height: height,
      layoutId: 'root-paint',
      textScaler: scaler,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 1000,
        maxTextCodeUnits: 10000,
        maxRuns: 10000,
        maxIssuedLeases: 512,
      ),
    );
    for (var i = 0; !session.isComplete && i < 10000; i++) {
      final before = cache.layoutBuildCount;
      session.advance(maxEvents: 1, maxLines: 1);
      expect(cache.layoutBuildCount - before, lessThanOrEqualTo(1));
    }
    expect(session.isComplete, true);
  }
  final cache = ForumBodyParagraphCache(
    maxEntries: 128,
    maxEstimatedBytes: 1 << 24,
  );
  late final ForumBodyTextPageSession session;
  void close() {
    session.close();
    cache.close();
  }
}

List<ForumBodyPreparedTextFragment> _prepare(_Fixture fixture, int page) {
  final job = fixture.session.openPagePreparation(page);
  final expectedHandles = job.expectedNativeLeaseCount;
  for (var i = 0; !job.isReady && i < 10000; i++) {
    job.advance(maxFragments: 1, maxParts: 1);
  }
  expect(job.isReady, true);
  final fragments = job.takeFragments();
  expect(fragments.expand((f) => f.nativeLeases).length, expectedHandles);
  return fragments;
}

Future<ui.Image> _mount(
  WidgetTester tester,
  _Fixture fixture,
  List<ForumBodyPreparedTextFragment> fragments,
  GlobalKey key, {
  int ratio = 1,
  int page = 0,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xffffffff),
            child: SizedBox(
              width: 280,
              height: fixture.session.snapshot.height + 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 20,
                    top: 20,
                    width: fixture.session.snapshot.width,
                    height: fixture.session.snapshot.height,
                    child: ForumBodyTextPageSurface.prepared(
                      snapshot: fixture.session.snapshot,
                      pageIndex: page,
                      layoutId: 'root-paint',
                      fragments: fragments,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(
    () => boundary.toImage(pixelRatio: ratio.toDouble()),
  ))!;
}

Future<List<int>> _pixel(
  WidgetTester tester,
  ui.Image image,
  Offset point,
  int ratio,
) async {
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final offset =
      ((point.dy * ratio).floor() * image.width + (point.dx * ratio).floor()) *
      4;
  return bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 4).toList();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (name, children) in [
    ('column', _column),
    ('segment', _segment),
    ('space', _space),
  ]) {
    for (final direction in TextDirection.values) {
      for (final under in [false, true]) {
        testWidgets(
          'one root plane paints once and excludes annotation ($name,$direction,under=$under)',
          (tester) async {
            final fixture = _Fixture(
              children,
              direction: direction,
              under: under,
            );
            addTearDown(fixture.close);
            final fragments = _prepare(fixture, 0);
            final view =
                (fragments.single as ForumBodyPreparedInlineFragment).view;
            expect(view.containerBackgrounds, hasLength(1));
            final region = view.containerBackgrounds.single.rect;
            expect(region.height, 20);
            final counts = (
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
            );
            final image = await _mount(
              tester,
              fixture,
              fragments,
              GlobalKey(),
              ratio: 3,
            );
            try {
              final origin = Offset(
                20 + fixture.session.snapshot[0].fragments.single.left,
                20 + fixture.session.snapshot[0].fragments.single.top,
              );
              expect(await _pixel(tester, image, region.center + origin, 3), [
                255,
                127,
                127,
                255,
              ]);
              final outside =
                  Offset(
                    region.center.dx,
                    under ? region.bottom + 2 : region.top - 2,
                  ) +
                  origin;
              expect(await _pixel(tester, image, outside, 3), [
                255,
                255,
                255,
                255,
              ]);
              expect((
                fixture.cache.layoutBuildCount,
                fixture.cache.pictureBuildCount,
              ), counts);
            } finally {
              image.dispose();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            expect(fixture.cache.activeLeases, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final ratio in [1, 3]) {
    testWidgets(
      'root natural box can exceed child frame but remains clipped to the page (DPR$ratio)',
      (tester) async {
        final fixture = _Fixture(_column, rootSize: 40, height: 32);
        addTearDown(fixture.close);
        final fragments = _prepare(fixture, 0);
        final view = (fragments.single as ForumBodyPreparedInlineFragment).view;
        final region = view.containerBackgrounds.single.rect;
        expect(region.height, 40);
        expect(region.bottom, greaterThan(view.height));
        expect(region.bottom, greaterThan(fixture.session.snapshot.height));
        final image = await _mount(
          tester,
          fixture,
          fragments,
          GlobalKey(),
          ratio: ratio,
        );
        try {
          final origin = Offset(
            20 + fixture.session.snapshot[0].fragments.single.left,
            20 + fixture.session.snapshot[0].fragments.single.top,
          );
          expect(
            await _pixel(
              tester,
              image,
              Offset(region.center.dx, fixture.session.snapshot.height - 1) +
                  origin,
              ratio,
            ),
            [255, 127, 127, 255],
          );
          expect(
            await _pixel(
              tester,
              image,
              Offset(region.center.dx + origin.dx, 19),
              ratio,
            ),
            [255, 255, 255, 255],
          );
          expect(
            await _pixel(
              tester,
              image,
              Offset(
                region.center.dx + origin.dx,
                21 + fixture.session.snapshot.height,
              ),
              ratio,
            ),
            [255, 255, 255, 255],
          );
        } finally {
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }
  for (final direction in TextDirection.values) {
    testWidgets(
      'one root spanning rows and pages keeps single alpha and exact visible ownership ($direction)',
      (tester) async {
        final fixture = _Fixture(
          '${List.filled(8, '<rb style="font-size:20px;line-height:1">A</rb>').join()}'
          '${List.filled(8, '<rt style="font-size:10px;line-height:1">x</rt>').join()}',
          width: 70,
          height: 65,
          direction: direction,
        );
        addTearDown(fixture.close);
        expect(fixture.session.snapshot.length, greaterThan(1));
        final atoms = <int>{};
        for (var page = 0; page < fixture.session.snapshot.length; page++) {
          final fragments = _prepare(fixture, page);
          final view =
              (fragments.single as ForumBodyPreparedInlineFragment).view;
          expect(view.containerBackgrounds.length, view.lines.length);
          for (final atom in view.atomIndices) {
            expect(atoms.add(atom), true);
          }
          final before = (
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          );
          final image = await _mount(
            tester,
            fixture,
            fragments,
            GlobalKey(),
            page: page,
            ratio: 3,
          );
          try {
            final fragment = fixture.session.snapshot[page].fragments.single;
            for (final region in view.containerBackgrounds) {
              expect(
                await _pixel(
                  tester,
                  image,
                  region.rect.center +
                      Offset(20 + fragment.left, 20 + fragment.top),
                  3,
                ),
                [255, 127, 127, 255],
              );
            }
            expect((
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
            ), before);
          } finally {
            image.dispose();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          expect(fixture.cache.activeLeases, 0);
        }
        expect(atoms, Set.of(List.generate(8, (index) => index)));
      },
    );
  }
  testWidgets('root overflow stays behind an earlier paragraph glyph', (
    tester,
  ) async {
    final fixture = _Fixture(
      _column,
      rootSize: 40,
      before: '<p style="margin:0;line-height:1">A</p>',
      ink: const Color(0xff000000),
    );
    addTearDown(fixture.close);
    final fragments = _prepare(fixture, 0);
    expect(fragments, hasLength(2));
    final page = fixture.session.snapshot[0];
    final view = (fragments[1] as ForumBodyPreparedInlineFragment).view;
    final earlier = page.fragments.first;
    final point = Offset(earlier.left + 10, earlier.top + earlier.height - 2);
    final later = page.fragments[1];
    expect(
      view.containerBackgrounds.single.rect
          .shift(Offset(later.left, later.top))
          .contains(point),
      true,
    );
    final image = await _mount(
      tester,
      fixture,
      fragments,
      GlobalKey(),
      ratio: 3,
    );
    try {
      expect(await _pixel(tester, image, point + const Offset(20, 20), 3), [
        0,
        0,
        0,
        255,
      ]);
    } finally {
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.cache.activeLeases, 0);
  });
  for (final explicit in [false, true]) {
    for (final inherit in [false, true]) {
      for (final scope in ForumBodyStyleScope.values) {
        testWidgets(
          'RTC stays an abstract background container; explicit child inherit=$inherit, rt=$explicit, scope=$scope',
          (tester) async {
            final inner = explicit
                ? '<rt${inherit ? ' style="background:inherit"' : ''}>x y</rt>'
                : (inherit
                      ? '<span style="background:inherit">x y</span>'
                      : 'x y');
            final fixture = _Fixture(
              '<rb>A</rb><rb>B</rb><rtc style="background:#00ff00">$inner</rtc>',
              rootBackground: 'transparent',
              backgroundScope: scope,
            );
            addTearDown(fixture.close);
            final fragments = _prepare(fixture, 0);
            for (final fragment
                in fragments.whereType<ForumBodyPreparedInlineFragment>()) {
              expect(fragment.view.containerBackgrounds, isEmpty);
            }
            final image = await _mount(
              tester,
              fixture,
              fragments,
              GlobalKey(),
              ratio: 3,
            );
            try {
              final bytes = (await tester.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
              ))!;
              var green = false;
              for (var i = 0; i < bytes.lengthInBytes; i += 4) {
                if (bytes.getUint8(i) == 0 &&
                    bytes.getUint8(i + 1) == 255 &&
                    bytes.getUint8(i + 2) == 0) {
                  green = true;
                  break;
                }
              }
              expect(green, inherit && scope != ForumBodyStyleScope.forceAll);
            } finally {
              image.dispose();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            expect(fixture.cache.activeLeases, 0);
          },
        );
      }
    }
  }
}
