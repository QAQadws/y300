import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/inline_image_fixture.dart';

ForumBodyTextPageSession _open(
  String html, {
  double width = 100,
  double height = 60,
  int? handles,
  ForumBodyLength indent = ForumBodyLength.zero,
  List<ForumBodyInlineImageInput>? imageInputs,
  int issuedLeases = 8,
  int? pageImages,
  ForumBodyPageColumns columns = const ForumBodyPageColumns(),
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'discuz-float-page',
    conversionIdentity: 'none',
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 22,
  );
  addTearDown(cache.close);
  final session = ForumBodyTextPageSession(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'discuz-float-page',
      linkColor: const Color(0xff0000ff),
      paragraphAfter: 0,
      firstLineIndent: indent,
    ),
    cache: cache,
    limits: ForumBodyTextPageSessionLimits(
      maxPages: 16,
      maxFragments: 48,
      maxParagraphs: 48,
      maxTextCodeUnits: 2048,
      maxRuns: 128,
      maxIssuedLeases: issuedLeases,
    ),
    layoutId: 'discuz-float-page',
    width: width,
    height: height,
    columns: columns,
    captureFloats: true,
    maxNativeHandlesPerPage: handles,
    maxNativeEntriesPerPage: handles,
    maxNativeEstimatedBytesPerPage: 1 << 20,
    maxImagesPerPage: pageImages,
    inlineImageResolver: imageInputs == null
        ? null
        : (_, element, style) {
            final input = ForumBodyInlineImageInput.replaced(
              source: ForumBodyInlineImageSource(
                document: document,
                element: element,
                image: const InlineImageDescription(),
              ),
              box: style.box,
              intrinsicSize: const Size(40, 10),
              maxHeight: 100,
            );
            imageInputs.add(input);
            return input;
          },
  );
  addTearDown(session.close);
  return session;
}

void _advance(ForumBodyTextPageSession session, {int? untilPages}) {
  var steps = 0;
  while (!session.isComplete &&
      (untilPages == null || session.snapshot.length < untilPages)) {
    if (++steps > 2000) fail('Float session did not reach its target');
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 4);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
}

List<ForumBodyPreparedTextFragment> _prepare(
  ForumBodyTextPageSession session,
  int index,
) {
  final preparation = session.openPagePreparation(index);
  try {
    var steps = 0;
    while (!preparation.isReady) {
      if (++steps > 2000) fail('Float fragments did not become ready');
      preparation.advance(maxFragments: 1, maxParts: 4);
    }
    return preparation.takeFragments();
  } finally {
    preparation.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  testWidgets(
    'opposite floats paint in one page and clear moves the cursor by side',
    (tester) async {
      final session = _open(
        '<span style="float:left;margin:2px 5px 0 0;background-color:red">AA</span>'
        '<span style="float:right;margin-left:5px;height:30px">BBB</span>'
        '<br style="clear:left"><span style="float:left">CC</span>'
        '<br style="clear:both">tail',
      );
      _advance(session);
      final snapshot = session.snapshot;
      final page = snapshot.single;
      expect(page.usedHeight, 40);
      expect(page.fragments.map((fragment) => (fragment.left, fragment.top)), [
        (0.0, 2.0),
        (70.0, 0.0),
        (0.0, 12.0),
        (0.0, 30.0),
      ]);
      expect(page.fragments.map((fragment) => fragment.paragraphIndex), [
        0,
        1,
        2,
        3,
      ]);
      expect(page.backgrounds.single.color, const Color(0xffff0000));
      final deliveries = _prepare(session, 0);
      expect(deliveries.map((fragment) => fragment.projection.text), [
        'AA',
        'BBB',
        'CC',
        'tail',
      ]);
      expect(session.activeIssuedLeases, 4);
      final tapped = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: snapshot,
              pageIndex: 0,
              layoutId: snapshot.layoutId,
              fragments: deliveries,
              onSourceTap: (fragment, position) =>
                  tapped.add((fragment.paragraphIndex, position.sourceRune)),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(3, 6));
      await tester.tapAt(const Offset(74, 5));
      await tester.tapAt(const Offset(3, 16));
      expect(tapped, [(0, 0), (1, 2), (2, 6)]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(session.activeIssuedLeases, 0);
    },
  );

  test(
    'a float moves as a unit to the next page and preserves the first prefix',
    () {
      final session = _open(
        '<p>lead</p><span style="float:right;height:30px">AA</span>'
        '<br style="clear:both"><p>tail</p>',
        height: 32,
      );
      _advance(session, untilPages: 1);
      final prefix = session.snapshot;
      expect(prefix.single.fragments.single.paragraphIndex, 0);
      _advance(session);
      expect(prefix, hasLength(1));
      expect(session.snapshot, hasLength(3));
      expect(session.snapshot.first, same(prefix.first));
      final float = session.snapshot[1].fragments.single;
      expect((float.paragraphIndex, float.left, float.top), (1, 80.0, 0.0));
      expect(session.snapshot[1].usedHeight, 30);
      expect(session.snapshot.last.fragments.single.paragraphIndex, 2);
    },
  );

  test('a new column restores full line width after a floated band', () {
    final session = _open(
      '<span style="float:left;height:30px">AA</span>'
      'abcdefghijklmnopqrstuvwxyz',
      width: 130,
      height: 30,
      columns: const ForumBodyPageColumns(count: 2, gap: 10),
    );
    _advance(session);
    final page = session.snapshot.single;
    final [floated, beside, nextColumn] = page.fragments;
    expect(floated.isFloated, isTrue);
    expect((floated.left, floated.top, floated.width), (0, 0, 20));
    expect((beside.left, beside.top, beside.width), (20, 0, 40));
    expect((nextColumn.left, nextColumn.top, nextColumn.width), (70, 0, 60));
    expect(beside.sourceHint!.runeEnd, nextColumn.sourceHint!.runeStart);
    for (final fragment in _prepare(session, 0)) {
      fragment.close();
    }
    expect(session.activeIssuedLeases, 0);
  });

  test('a second float respects the draft native handle budget', () {
    final session = _open(
      '<span style="float:left"><ruby>AA<rt>a</rt></ruby></span>'
      '<span style="float:right"><ruby>BB<rt>b</rt></ruby></span>',
      handles: 4,
    );
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first.fragments.single.left, 0);
    expect(session.snapshot.last.fragments.single.left, 80);
    for (final index in [0, 1]) {
      final deliveries = _prepare(session, index);
      expect(deliveries.single.nativeLeases.length, greaterThan(2));
      deliveries.single.close();
    }
  });

  test('opposite float boxes move down when their margins leave no room', () {
    final session = _open(
      '<span style="float:left;margin-right:5px">AAA</span>'
      '<span style="float:right;margin-left:5px">BBB</span>',
      width: 50,
    );
    _advance(session);
    expect(
      session.snapshot.single.fragments.map(
        (fragment) => (fragment.left, fragment.top),
      ),
      [(0.0, 0.0), (20.0, 10.0)],
    );
  });

  test('text uses successive exclusion widths and keeps every source position', () {
    final text = 'A' * 48;
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      '<span style="float:right;width:20px;height:10px;margin-left:5px">R</span>'
      '$text',
      height: 80,
    );
    _advance(session);
    final page = session.snapshot.single;
    final bands = page.fragments.skip(2).toList();
    expect(bands.map((part) => (part.left, part.top, part.width)), [
      (35.0, 0.0, 40.0),
      (35.0, 10.0, 65.0),
      (0.0, 30.0, 100.0),
    ]);
    final fragments = _prepare(session, 0);
    var rawOffset = 2;
    final painted = StringBuffer();
    for (final (index, part) in bands.indexed) {
      expect(part.sourceHint!.runeStart, rawOffset);
      rawOffset = part.sourceHint!.runeEnd;
      final projected = fragments[index + 2].projection.text;
      painted.write(
        projected.substring(part.coverageStartUtf16, part.coverageEndUtf16),
      );
    }
    expect(rawOffset, 50);
    expect(painted.toString(), text);
    for (final fragment in fragments) {
      fragment.close();
    }
  });

  for (final margin in [5, 10]) {
    test(
      'text moves under the float when the remaining width is ${10 - margin}',
      () {
        final session = _open(
          '<span style="float:left;width:90px;height:20px;margin-right:${margin}px">L</span>'
          '<p>text after</p>',
        );
        _advance(session);
        final parts = session.snapshot.single.fragments;
        expect(parts, hasLength(2));
        expect(
          (parts.last.left, parts.last.top, parts.last.width),
          (0.0, 20.0, 100.0),
        );
        expect(parts.last.sourceHint, (runeStart: 1, runeEnd: 11));
      },
    );
  }

  test('a book page seal reflows only the unconsumed text at full width', () {
    final text = 'Z' * 28;
    final session = _open(
      '<span style="float:right;width:35px;height:25px;margin-left:5px">R</span>'
      '$text',
      height: 28,
    );
    _advance(session, untilPages: 1);
    final prefix = session.snapshot;
    final beside = prefix.single.fragments.last;
    expect((beside.left, beside.width, beside.height), (0.0, 60.0, 20.0));
    expect(beside.sourceHint, (runeStart: 1, runeEnd: 13));
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first, same(prefix.first));
    final continued = session.snapshot.last.fragments.single;
    expect((continued.left, continued.top, continued.width), (0.0, 0.0, 100.0));
    expect(continued.sourceHint, (runeStart: 13, runeEnd: 29));
  });

  test('a page-height float does not seal while there is room beside it', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      '${'A' * 20}',
      height: 30,
    );
    _advance(session);
    expect(session.snapshot, hasLength(2));
    final beside = session.snapshot.first.fragments.last;
    expect((beside.left, beside.width, beside.height), (35.0, 65.0, 30.0));
    expect(beside.sourceHint, (runeStart: 1, runeEnd: 19));
    final next = session.snapshot.last.fragments.single;
    expect((next.left, next.width, next.top), (0.0, 100.0, 0.0));
    expect(next.sourceHint, (runeStart: 19, runeEnd: 21));
  });

  test('a clear after wrapped text restores full width at the float bottom', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      'before<br style="clear:left">after',
    );
    _advance(session);
    final parts = session.snapshot.single.fragments;
    expect(parts.map((part) => (part.left, part.top, part.width)), [
      (0.0, 0.0, 30.0),
      (35.0, 0.0, 65.0),
      (0.0, 30.0, 100.0),
    ]);
    expect(parts[1].sourceHint, (runeStart: 1, runeEnd: 7));
    expect(parts[2].sourceHint, (runeStart: 8, runeEnd: 13));
  });

  test('a band change preserves author styles without indenting twice', () {
    final text = 'A' * 25;
    final session = _open(
      '<span style="float:left;width:30px;height:20px;margin-right:5px">L</span>'
      '<strong style="color:red">$text</strong>',
      indent: const ForumBodyLength(1, ForumBodyLengthUnit.em),
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => part.width), [30.0, 65.0, 100.0]);
    final deliveries = _prepare(session, 0);
    final beside = deliveries[1] as ForumBodyPreparedParagraphFragment;
    final after = deliveries[2] as ForumBodyPreparedParagraphFragment;
    expect(beside.lease.layout.firstLineIndent.appliedAdvance, greaterThan(0));
    expect(after.lease.layout.firstLineIndent.appliedAdvance, 0);
    expect(beside.runs.single.style.textStyle.color, const Color(0xffff0000));
    expect(after.runs.single.style.textStyle.color, const Color(0xffff0000));
    expect(
      page.fragments[1].sourceHint!.runeEnd,
      page.fragments[2].sourceHint!.runeStart,
    );
    for (final fragment in deliveries) {
      fragment.close();
    }
  });

  test('terminal empty lines do not replay floats from the previous row', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px">L</span>text<br><br>',
    );
    _advance(session);
    final parts = session.snapshot.single.fragments;
    expect(
      parts.where((part) => part.sourceHint?.runeStart == 0),
      hasLength(1),
    );
    expect(parts.last.sourceHint, isNull);
    expect(parts.last.left, 30);
  });

  testWidgets(
    'an inline float shares the actual line and preserves both text sources',
    (tester) async {
      final session = _open(
        '<b>AB </b><span style="float:right;width:30px;height:20px;margin-left:5px">F</span>'
        '<span style="color:red"> CD</span>',
      );
      _advance(session);
      final snapshot = session.snapshot;
      final page = snapshot.single;
      expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
        (70.0, 0.0, 30.0),
        (0.0, 0.0, 65.0),
      ]);
      final deliveries = _prepare(session, 0);
      expect(deliveries.last.projection.text, 'AB CD');
      expect(
        deliveries.last.runs.last.style.textStyle.color,
        const Color(0xffff0000),
      );
      final taps = <int>[];
      final selections = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: snapshot,
              pageIndex: 0,
              layoutId: snapshot.layoutId,
              fragments: deliveries,
              onSourceTap: (_, position) => taps.add(position.sourceRune),
              onSourceLongPress: (_, selection) =>
                  selections.add(selection.text),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(3, 5));
      await tester.tapAt(const Offset(33, 5));
      await tester.tapAt(const Offset(73, 5));
      expect(taps, [0, 5, 3]);
      await tester.longPressAt(const Offset(37, 5));
      expect(selections, ['AB CD']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(session.activeIssuedLeases, 0);
    },
  );

  test('only the final prefix row is reflowed when a float is encountered', () {
    final session = _open(
      '${'A' * 24}<span style="float:left;width:35px;margin-right:5px">F</span>BC',
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
      (0.0, 0.0, 100.0),
      (0.0, 20.0, 35.0),
      (40.0, 20.0, 60.0),
    ]);
    expect(page.fragments[0].sourceHint, (runeStart: 0, runeEnd: 20));
    expect(page.fragments[1].sourceHint, (runeStart: 24, runeEnd: 25));
    final deliveries = _prepare(session, 0);
    expect(deliveries.last.projection.text, 'AAAABC');
    expect(deliveries.last.projection.sourceAtUtf16(5).sourceRune, 26);
    for (final delivery in deliveries) {
      delivery.close();
    }
  });

  test('a float moves below a preceding line that occupies its space', () {
    final session = _open(
      'AAAAAAAA<span style="float:left;width:35px;margin-right:5px">F</span>BC',
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
      (0.0, 0.0, 100.0),
      (0.0, 10.0, 35.0),
      (40.0, 10.0, 60.0),
    ]);
    expect(page.fragments.map((part) => part.sourceHint), [
      (runeStart: 0, runeEnd: 8),
      (runeStart: 8, runeEnd: 9),
      (runeStart: 9, runeEnd: 11),
    ]);
  });

  test('multiple floats can encounter the same still-pending line', () {
    final session = _open(
      'AB<span style="float:left;width:20px">L</span>'
      'C<span style="float:right;width:25px">R</span>D',
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
      (0.0, 0.0, 20.0),
      (75.0, 0.0, 25.0),
      (20.0, 0.0, 55.0),
    ]);
    final deliveries = _prepare(session, 0);
    expect(deliveries.last.projection.text, 'ABCD');
    for (final delivery in deliveries) {
      delivery.close();
    }
  });

  test(
    'a too-tall inline float moves without replaying the published prefix',
    () {
      final session = _open(
        '<p>lead</p>AB<span style="float:left;width:20px;height:30px">F</span>CD',
        height: 35,
      );
      _advance(session, untilPages: 1);
      final prefix = session.snapshot;
      expect(prefix.single.fragments.map((part) => part.sourceHint), [
        (runeStart: 0, runeEnd: 4),
        (runeStart: 4, runeEnd: 6),
      ]);
      _advance(session);
      expect(session.snapshot, hasLength(2));
      expect(session.snapshot.first, same(prefix.first));
      expect(session.snapshot.last.fragments.map((part) => part.sourceHint), [
        (runeStart: 6, runeEnd: 7),
        (runeStart: 7, runeEnd: 9),
      ]);
    },
  );

  test('a line-band change continues inside a single-layer ruby group', () {
    final session = _open(
      '<span style="float:left;width:60px;height:12px">F</span>'
      '<ruby><rb>A</rb><rb>B</rb><rb>C</rb><rb>D</rb><rb>E</rb>'
      '<rt>a</rt><rt>b</rt><rt>c</rt><rt>d</rt><rt>e</rt></ruby>tail',
      height: 100,
      issuedLeases: 24,
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => part.width), [60.0, 40.0, 100.0]);
    final delivered = _prepare(session, 0);
    final pieces = [
      for (final (index, part) in page.fragments.indexed.skip(1))
        delivered[index].projection.text.substring(
          part.coverageStartUtf16,
          part.coverageEndUtf16,
        ),
    ];
    expect(pieces, ['AaBbCcDd', 'Eetail']);
    expect(delivered[1].projection.sourceAtUtf16(7).sourceRune, 9);
    expect(delivered[2].projection.sourceAtUtf16(0).sourceRune, 5);
    for (final fragment in delivered) {
      fragment.close();
    }
  });

  test('identical image URLs at one text fence continue by native slot', () {
    final images = <ForumBodyInlineImageInput>[];
    final session = _open(
      '<span style="float:left;width:40px;height:10px">F</span>'
      '${'<img src="same.png" style="display:inline;width:70%">' * 3}',
      imageInputs: images,
      height: 100,
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => part.width), [40.0, 60.0, 100.0]);
    expect(images, hasLength(3));
    expect(page.fragments[1].imagePaths, [images[0].element.path]);
    expect(page.fragments[2].imagePaths, [
      images[1].element.path,
      images[2].element.path,
    ]);
    final delivered = _prepare(session, 0);
    final before =
        (delivered[1] as ForumBodyPreparedInlineFragment).view.images.values;
    final after =
        (delivered[2] as ForumBodyPreparedInlineFragment).view.images.values;
    expect(before.single.input.source, same(images[0].source));
    expect(before.single.input.dimensions.size.width, closeTo(42, 1e-6));
    expect(after.map((image) => image.input.source), [
      images[1].source,
      images[2].source,
    ]);
    expect(after.map((image) => image.input.dimensions.size.width), [
      70.0,
      70.0,
    ]);
    for (final fragment in delivered) {
      fragment.close();
    }
  });

  test('a sealed mixed page retains the next zero-length image occurrence', () {
    final images = <ForumBodyInlineImageInput>[];
    final session = _open(
      '<span style="float:left;width:40px;height:30px">F</span>'
      '${'<img src="same.png" style="display:inline;width:70%">' * 2}',
      imageInputs: images,
      pageImages: 1,
    );
    _advance(session, untilPages: 1);
    final prefix = session.snapshot;
    expect(prefix.single.fragments.last.imagePaths, [
      images.first.element.path,
    ]);
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first, same(prefix.first));
    expect(session.snapshot.last.fragments.single.imagePaths, [
      images.last.element.path,
    ]);
    final delivery =
        _prepare(session, 1).single as ForumBodyPreparedInlineFragment;
    expect(
      delivery.view.images.values.single.input.source,
      same(images.last.source),
    );
    expect(delivery.view.images.values.single.rect.width, 70);
    delivery.close();
  });

  test(
    'the text before a float can join a following ruby on the same line',
    () {
      final session = _open(
        '<b>AB</b><span style="float:right;width:30px;height:20px">F</span>'
        '<ruby>C<rt>c</rt></ruby>D',
      );
      _advance(session);
      final page = session.snapshot.single;
      expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
        (70.0, 0.0, 30.0),
        (0.0, 0.0, 70.0),
      ]);
      final delivered = _prepare(session, 0);
      expect(delivered.last.projection.text, 'ABCcD');
      expect(delivered.last.projection.sourceAtUtf16(2).sourceRune, 3);
      for (final fragment in delivered) {
        fragment.close();
      }
    },
  );

  test('ruby on both sides of an encountered float shares one native row', () {
    final session = _open(
      '<ruby><rb>A</rb><rb>B</rb><rt>a</rt><rt>b</rt></ruby> '
      '<span style="float:right;width:35px;height:18px">F</span> '
      '<ruby>C<rt>c</rt></ruby>D',
      issuedLeases: 24,
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => (part.left, part.top, part.width)), [
      (65.0, 0.0, 35.0),
      (0.0, 0.0, 65.0),
    ]);
    final delivered = _prepare(session, 0);
    expect(delivered.last.projection.text, 'AaBb CcD');
    expect(delivered.last.projection.sourceAtUtf16(0).sourceRune, 0);
    expect(delivered.last.projection.sourceAtUtf16(1).sourceRune, 2);
    expect(delivered.last.projection.sourceAtUtf16(5).sourceRune, 7);
    for (final part in delivered) {
      part.close();
    }
  });

  test('only the pending same-URL image slot moves beside a float', () {
    final images = <ForumBodyInlineImageInput>[];
    final session = _open(
      '${'<img src="same.png" style="display:inline;width:45px">' * 3}'
      '<span style="float:left;width:40px;height:20px">F</span>'
      '<img src="same.png" style="display:inline;width:10px">Z',
      imageInputs: images,
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(images, hasLength(4));
    expect(page.fragments.map((part) => part.imagePaths), [
      [images[0].element.path, images[1].element.path],
      isEmpty,
      [images[2].element.path, images[3].element.path],
    ]);
    expect(page.fragments[0].top, lessThan(page.fragments[1].top));
    expect(page.fragments[1].top, page.fragments[2].top);
    expect(page.fragments[2].left, 40);
    final delivered = _prepare(session, 0);
    final pending = delivered.last as ForumBodyPreparedInlineFragment;
    expect(pending.projection.text, 'Z');
    expect(pending.view.images.values.map((image) => image.input.source), [
      images[2].source,
      images[3].source,
    ]);
    for (final part in delivered) {
      part.close();
    }
  });

  test('a too-tall float leaves its held ruby on the stable prior page', () {
    final session = _open(
      '<p>lead</p><ruby>A<rt>a</rt></ruby>'
      '<span style="float:left;width:40px;height:35px">F</span>Z',
      height: 40,
    );
    _advance(session, untilPages: 1);
    final prefix = session.snapshot;
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first, same(prefix.single));
    final before = _prepare(session, 0);
    final after = _prepare(session, 1);
    expect(before.map((part) => part.projection.text), ['lead', 'Aa']);
    expect(after.map((part) => part.projection.text), ['F', 'Z']);
    for (final part in [...before, ...after]) {
      part.close();
    }
  });

  test(
    'the held image reserves its page slot before a float with an image',
    () {
      final images = <ForumBodyInlineImageInput>[];
      final session = _open(
        '<img src="same.png" style="display:inline;width:15px">'
        '<span style="float:left;width:30px">'
        '<img src="same.png" style="display:inline;width:15px"></span>Z',
        imageInputs: images,
        pageImages: 1,
      );
      _advance(session);
      expect(images, hasLength(2));
      expect(session.snapshot, hasLength(2));
      expect(session.snapshot.first.fragments.single.imagePaths, [
        images[0].element.path,
      ]);
      expect(session.snapshot.last.fragments.first.imagePaths, [
        images[1].element.path,
      ]);
      for (final (index, page) in session.snapshot.indexed) {
        expect(page.fragments.expand((part) => part.imagePaths), hasLength(1));
        final delivered = _prepare(session, index);
        final image = delivered.first as ForumBodyPreparedInlineFragment;
        expect(
          image.view.images.values.single.input.source,
          same(images[index].source),
        );
        for (final part in delivered) {
          part.close();
        }
      }
    },
  );
}
