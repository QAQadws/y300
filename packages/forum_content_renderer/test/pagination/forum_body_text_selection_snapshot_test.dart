import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, SelectionArea;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(String html, {double height = 60}) {
    final doc = const ForumBodyParser().parse(
      html: html,
      sourceId: 'selection',
      conversionIdentity: 'none',
    );
    cache = ForumBodyParagraphCache(maxEntries: 64, maxEstimatedBytes: 1 << 24);
    session = ForumBodyTextPageSession(
      document: doc,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 100000,
        maxRuns: 1000,
        maxIssuedLeases: 128,
      ),
      layoutId: 'selection',
      width: 200,
      height: height,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
    for (var i = 0; !session.isComplete; i++) {
      if (i > 10000) fail('selection source stalled');
      session.advance(maxEvents: 2, maxLines: 2);
    }
  }
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var i = 0; !job.isReady; i++) {
        if (i > 10000) fail('selection view stalled');
        job.advance(maxFragments: 1, maxParts: 1);
      }
      return job.takeFragments();
    } finally {
      job.close();
    }
  }

  ForumBodyTextSelectionSnapshot? at(
    ForumBodyPreparedTextFragment body,
    int page,
    int index,
    int offset, {
    int limit = 65536,
  }) {
    final box = body.glyphBoxes(offset, offset + 1).first;
    return forumBodyTextSelectionAt(
      binding: body,
      fragment: session.snapshot[page].fragments[index],
      pageSize: Size(200, session.snapshot.height),
      point: Offset(
        box.left + (box.right - box.left) * .25,
        (box.top + box.bottom) * .5,
      ),
      maxCodeUnits: limit,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('source highlight only paints complete visible graphemes', (
    tester,
  ) async {
    final f = _Fixture(
      '<p>A<ruby>字<rt>note</rt></ruby>'
      '<span style="visibility:hidden">secret</span>🦊e\u0301Z</p>',
    );
    final snapshot = f.session.snapshot;
    final fragments = f.prepare(0);
    final surface = ForumBodyTextPageSurface.prepared(
      snapshot: snapshot,
      pageIndex: 0,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    ForumBodySourceRange range(int start, int end) =>
        ForumBodySourceRange(snapshot.identity, start, end);
    const color = Color(0x5437aa00);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ForumBodyTextHighlight(
            ranges: [range(1, 2)],
            color: color,
            child: surface,
          ),
        ),
      ),
    );
    expect(surface.locateSourceRanges([range(1, 2)]), hasLength(1));
    expect(surface.locateSourceRanges([range(2, 12)]), isEmpty);
    expect(surface.locateSourceRanges([range(12, 13)]), hasLength(1));
    expect(surface.locateSourceRanges([range(13, 14)]), isEmpty);
    expect(surface.locateSourceRanges([range(13, 15)]), hasLength(1));
    final wrong = ForumBodySourceRange(
      ForumBodyIdentity(
        sourceId: snapshot.identity.sourceId,
        inputHash: snapshot.identity.inputHash,
        conversionIdentity: 'different',
        parserRevision: snapshot.identity.parserRevision,
      ),
      1,
      2,
    );
    expect(surface.locateSourceRanges([wrong]), isEmpty);
    expect(find.byWidget(surface), paints..rect(color: color));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(surface.locateSourceRanges([range(1, 2)]), isEmpty);
    expect(f.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flutter selection copies only the current visible base text', (
    tester,
  ) async {
    final fixture = _Fixture(
      '<p>甲<ruby>字<rt>note</rt></ruby>'
      '<span style="visibility:hidden">secret</span>🦊e\u0301 乙</p>',
    );
    final fragments = fixture.prepare(0);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: Align(
              alignment: Alignment.topLeft,
              child: ForumBodyTextPageSurface.prepared(
                snapshot: fixture.session.snapshot,
                pageIndex: 0,
                layoutId: 'selection',
                fragments: fragments,
              ),
            ),
          ),
        ),
      ),
    );
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(selected, '甲字🦊e\u0301 乙');
    region.clearSelection();
    await tester.pump();
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flow copy joins source paragraphs across scrolling slices', (
    tester,
  ) async {
    final text = '甲' * 40;
    const url = 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=521519';
    const longer = '$url&page=2';
    final fixture = _Fixture(
      '<p>$text</p><p>Second</p><p>$url</p><p>$longer</p>'
      '<p>$url\n&amp;page=3</p>',
      height: 10,
    );
    final snapshot = fixture.session.snapshot;
    expect(snapshot.length, greaterThan(2));
    final fragments = [
      for (var i = 0; i < snapshot.length; i++) fixture.prepare(i),
    ];
    final flow = GlobalKey<ForumBodyFlowSelectionScopeState>();
    String? selected;
    Widget build({required bool enabled}) => MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: ForumBodyFlowSelectionScope(
            key: flow,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < fragments.length; i++)
                    ForumBodyTextPageSurface.prepared(
                      snapshot: snapshot,
                      pageIndex: i,
                      layoutId: 'selection',
                      fragments: fragments[i],
                      selectionEnabled: enabled,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(enabled: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(selected, '$text\nSecond\n$url\n$longer\n$url &page=3');
    final selection = flow.currentState!;
    expect(selection.selectedText, selected);
    final links = const ForumHttpTextLinkDetector().detect(selected!).links;
    expect(links.map((link) => link.text), [url, longer, url]);
    expect(selection.confirmsSelectedLink(links[0]), isTrue);
    expect(selection.confirmsSelectedLink(links[1]), isTrue);
    expect(selection.confirmsSelectedLink(links[2]), isFalse);
    expect(
      selection.confirmsSelectedLink(
        ForumHttpTextLink(
          start: links[1].start,
          end: links[1].start + url.length,
          text: url,
          uri: Uri.parse(url),
        ),
      ),
      isFalse,
    );

    await tester.pumpWidget(build(enabled: false));
    expect(flow.currentState!.selectedText, isNull);
    expect(fragments.expand((page) => page).every((f) => f.isActive), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse drag selects the actual native glyph range in reverse', (
    tester,
  ) async {
    final fixture = _Fixture('<p>First second third</p>');
    final fragments = fixture.prepare(0);
    final binding = fragments.single;
    final snapshots = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) => snapshots.add(content?.plainText),
            child: Align(
              alignment: Alignment.topLeft,
              child: ForumBodyTextPageSurface.prepared(
                snapshot: fixture.session.snapshot,
                pageIndex: 0,
                layoutId: 'selection',
                fragments: fragments,
              ),
            ),
          ),
        ),
      ),
    );
    final fragment = fixture.session.snapshot.single.fragments.single;
    final origin =
        tester.getTopLeft(find.byType(ForumBodyTextPageSurface)) +
        Offset(fragment.left, fragment.top);
    final start = binding.glyphBoxes(6, 7).single.toRect();
    final end = binding.glyphBoxes(11, 12).single.toRect();
    final drag = await tester.startGesture(
      origin + Offset(end.right - 1, end.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(origin + Offset(start.left + 1, start.center.dy));
    await drag.up();
    await tester.pump();
    expect(snapshots.last, 'second');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });
  test(
    'code copy preserves whitespace, excludes hidden text and source-free numbers',
    () {
      final f = _Fixture(
        '<div class="blockcode"><ol><li> A<span style="visibility:hidden">secret</span>B </li></ol></div>',
      );
      final bindings = f.prepare(0);
      final b = bindings.single;
      try {
        final copy = f.at(b, 0, 0, 1)!;
        expect(copy.text, ' AB ');
        expect(copy.position.sourceRune, 1);
        expect(copy.isCode, isTrue);
        expect(copy.isAnnotation, isFalse);
        expect(f.at(b, 0, 0, 2), isNull);
        expect(f.at(b, 0, 0, 1, limit: 1), isNull);
        expect(
          forumBodyTextSelectionAt(
            binding: b,
            fragment: f.session.snapshot[0].fragments.single,
            pageSize: const Size(200, 60),
            point: const Offset(150, 2),
          ),
          isNull,
        );
      } finally {
        b.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'single-level base and explicit annotation keep their actual independent windows',
    () {
      final f = _Fixture('<p>x<ruby>AB<rt>xy</rt></ruby>z</p>');
      final bindings = f.prepare(0);
      final b = bindings.single as ForumBodyPreparedInlineFragment;
      try {
        for (final (text, annotation) in [('AB', false), ('xy', true)]) {
          final window = b.view.content.contexts.firstWhere(
            (w) => w.content.projection.text == text,
          );
          final copy = f.at(b, 0, 0, window.startUtf16)!;
          expect(copy.text, text);
          expect(copy.isAnnotation, annotation);
          expect(
            copy.position.sourceRune,
            window.content.projection.sourceAtUtf16(0).sourceRune,
          );
        }
      } finally {
        b.close();
      }
    },
  );
  test(
    'local snapshots preserve CJK, emoji, combining and RTL logical text',
    () {
      for (final (html, expected, start, end) in [
        ('<p>甲<span>乙</span>🦊é</p>', '甲乙🦊é', 2, 4),
        ('<p dir="rtl">אב גד</p>', 'אב גד', 0, 1),
      ]) {
        final f = _Fixture(html);
        final body = f.prepare(0).single;
        try {
          final box = body.glyphBoxes(start, end).first;
          final copy = forumBodyTextSelectionAt(
            binding: body,
            fragment: f.session.snapshot[0].fragments.single,
            pageSize: const Size(200, 60),
            point: Offset(
              box.left + (box.right - box.left) * .25,
              (box.top + box.bottom) * .5,
            ),
          );
          expect(copy?.text, expected);
          expect(copy?.position.isExact, isTrue);
        } finally {
          body.close();
        }
      }
    },
  );

  test('hidden interiors remove complete graphemes across style seams', () {
    final f = _Fixture('<p>A👩<span style="visibility:hidden">‍</span>👧B</p>');
    final b = f.prepare(0).single;
    try {
      expect(f.at(b, 0, 0, 0)!.text, 'AB');
    } finally {
      b.close();
    }
  });
  test('continuation copy stays in the actually visible line window', () {
    final f = _Fixture('<pre>${'word ' * 100}</pre>', height: 20);
    expect(f.session.snapshot.length, greaterThan(1));
    final b = f.prepare(1).single;
    final fragment = f.session.snapshot[1].fragments.single;
    final expected = b.projection.text.substring(
      fragment.coverageStartUtf16,
      fragment.coverageEndUtf16,
    );
    expect(f.at(b, 1, 0, fragment.coverageStartUtf16)!.text, expected);
    b.close();
    expect(
      forumBodyTextSelectionAt(
        binding: b,
        fragment: fragment,
        pageSize: const Size(200, 20),
        point: const Offset(1, 1),
      ),
      isNull,
    );
  });
  testWidgets(
    'long press keeps body leases, short taps and drag cancellation',
    (tester) async {
      final f = _Fixture('<p>abc</p>');
      final bindings = f.prepare(0);
      var taps = 0;
      final copies = <String>[];
      Widget page({bool enabled = true}) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 60,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: f.session.snapshot,
              pageIndex: 0,
              layoutId: 'selection',
              fragments: bindings,
              onSourceTap: (_, _) => taps++,
              onSourceLongPress: enabled ? (_, s) => copies.add(s.text) : null,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.tapAt(const Offset(2, 5));
      expect(taps, 1);
      expect(copies, isEmpty);
      await tester.longPressAt(const Offset(2, 5));
      expect(copies, ['abc']);
      expect(taps, 1);
      final held = await tester.startGesture(const Offset(2, 5));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(page(enabled: false));
      await tester.pump(const Duration(milliseconds: 600));
      await held.cancel();
      expect(copies, ['abc']);
      expect(bindings.single.isActive, isTrue);
      await tester.pumpWidget(page());
      final drag = await tester.startGesture(const Offset(2, 5));
      await drag.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await drag.up();
      expect(copies, ['abc']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
