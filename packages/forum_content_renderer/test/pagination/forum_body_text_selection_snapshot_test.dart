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
