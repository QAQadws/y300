import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent content(String html) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'surface',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 20,
        fontFamily: 'Ahem',
        color: Color(0xff000000),
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
  );
}

Widget host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  testWidgets(
    'two line surfaces share one layout and hit their own source range',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final input = content('<p>abcdefghij klmnopqrst uvwxyz</p>');
      final a = cache.acquire(content: input, width: 80);
      final b = cache.acquire(content: input, width: 80);
      final hits = <int>[];
      final expected = b.layout
          .fragment(2, 4)
          .sourceAt(const Offset(1, 10))
          .sourceRune;
      await tester.pumpWidget(
        host(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForumBodyParagraphSurface(lease: a, endLine: 2),
              ForumBodyParagraphSurface(
                key: const ValueKey('second'),
                lease: b,
                startLine: 2,
                endLine: 4,
                onSourceTap: (position) => hits.add(position.sourceRune),
              ),
            ],
          ),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('second'))) +
            const Offset(1, 10),
      );
      expect(hits, [expected]);
      expect(cache.layoutBuildCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'reparenting cancels a tap recorded in the old local coordinates',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final lease = cache.acquire(content: content('<p>abc</p>'), width: 200);
      final key = GlobalKey();
      var taps = 0;
      Widget surface() => ForumBodyParagraphSurface(
        key: key,
        lease: lease,
        onSourceTap: (_) => taps++,
      );
      await tester.pumpWidget(host(surface()));
      final gesture = await tester.startGesture(const Offset(1, 10));
      await tester.pumpWidget(
        host(
          Padding(padding: const EdgeInsets.only(left: 50), child: surface()),
        ),
      );
      await gesture.up();
      await tester.pump();
      expect(taps, 0);
      expect(cache.activeLeases, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'surface uses shared geometry and releases its lease on disposal',
    (tester) async {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final lease = cache.acquire(
        content: content('<p>abc def ghi</p>'),
        width: 200,
      );
      final height = lease.layout.height;
      final positions = <int>[];
      await tester.pumpWidget(
        host(
          IntrinsicHeight(
            child: IntrinsicWidth(
              child: ForumBodyParagraphSurface(
                lease: lease,
                onSourceTap: (position) => positions.add(position.sourceRune),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ForumBodyParagraphSurface)),
        Size(200, height),
      );
      final box = lease.layout.selectionBoxes(0, 1).single;
      await tester.tapAt(Offset(box.left + 1, (box.top + box.bottom) / 2));
      await tester.pump();
      expect(positions, [0]);
      expect(cache.layoutBuildCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(cache.activeLeases, 0);
      expect(lease.isActive, isFalse);
    },
  );

  testWidgets('replacing a layout cancels its in-flight tap', (tester) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final first = cache.acquire(content: content('<p>abc</p>'), width: 200);
    var oldTaps = 0;
    var newTaps = 0;
    await tester.pumpWidget(
      host(
        ForumBodyParagraphSurface(lease: first, onSourceTap: (_) => oldTaps++),
      ),
    );
    final gesture = await tester.startGesture(const Offset(1, 10));
    final next = cache.acquire(content: content('<p>def</p>'), width: 200);
    await tester.pumpWidget(
      host(
        ForumBodyParagraphSurface(lease: next, onSourceTap: (_) => newTaps++),
      ),
    );
    await gesture.up();
    await tester.pump();
    expect(oldTaps, 0);
    expect(newTaps, 0);
    expect(first.isActive, isFalse);
    await tester.tapAt(const Offset(1, 10));
    expect(newTaps, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('callback replacement keeps the same native layout', (
    tester,
  ) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final lease = cache.acquire(content: content('<p>abc</p>'), width: 200);
    var oldTaps = 0;
    var nextTaps = 0;
    await tester.pumpWidget(
      host(
        ForumBodyParagraphSurface(lease: lease, onSourceTap: (_) => oldTaps++),
      ),
    );
    await tester.pumpWidget(
      host(
        ForumBodyParagraphSurface(lease: lease, onSourceTap: (_) => nextTaps++),
      ),
    );
    await tester.tapAt(const Offset(1, 10));
    expect(oldTaps, 0);
    expect(nextTaps, 1);
    expect(cache.layoutBuildCount, 1);
    expect(cache.activeLeases, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('semantics exposes visible source text and heading role', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final lease = cache.acquire(
        content: content(
          '<h2>甲<span style="visibility:hidden">secret</span>乙</h2>',
        ),
        width: 400,
      );
      await tester.pumpWidget(host(ForumBodyParagraphSurface(lease: lease)));
      expect(find.bySemanticsLabel('甲乙'), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byType(ForumBodyParagraphSurface),
      );
      expect(semantics.getSemanticsData().flagsCollection.isHeader, isTrue);
      await tester.pumpWidget(const SizedBox());
    } finally {
      handle.dispose();
    }
  });

  testWidgets('owner close makes late paint/tap safe before unmount', (
    tester,
  ) async {
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 20,
    );
    final lease = cache.acquire(content: content('<p>abc</p>'), width: 200);
    var taps = 0;
    await tester.pumpWidget(
      host(ForumBodyParagraphSurface(lease: lease, onSourceTap: (_) => taps++)),
    );
    cache.close();
    tester
        .renderObject<RenderBox>(find.byType(ForumBodyParagraphSurface))
        .markNeedsPaint();
    await tester.pump();
    await tester.tapAt(const Offset(1, 10));
    expect(taps, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(cache.activeLeases, 0);
  });
}
