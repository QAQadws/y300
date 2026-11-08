import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle _reader() => ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
  paragraphAfter: 0,
);

final class _Fixture {
  _Fixture({
    String html = '<p>short</p>',
    int cacheEntries = 64,
    int maxPages = 10000,
    double? compactMinWidth,
    VoidCallback? onOpen,
  }) : cache = ForumBodyParagraphCache(
         maxEntries: cacheEntries,
         maxEstimatedBytes: 8 << 20,
       ) {
    final document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'flow-source',
      conversionIdentity: 'none',
    );
    source = ForumBodyFlowSource(
      width: 100,
      compactMinWidth: compactMinWidth,
      openSession: (width, {required probe}) {
        final session = ForumBodyTextPageSession(
          document: document,
          reader: _reader(),
          cache: cache,
          width: width,
          height: 20,
          layoutId: 'flow-${sessions.length}',
          textScaler: TextScaler.noScaling,
          limits: ForumBodyTextPageSessionLimits(
            maxPages: maxPages,
            maxFragments: 100000,
            maxParagraphs: 16384,
            maxTextCodeUnits: 1 << 20,
            maxRuns: 100000,
            maxIssuedLeases: 256,
          ),
          tableExtent: ForumBodyTableExtent.natural,
          intrinsicAvailableWidth: probe ? 100 : null,
          captureFloats: true,
        );
        sessions.add(session);
        onOpen?.call();
        return session;
      },
    );
    addTearDown(() {
      source.close();
      cache.close();
    });
  }

  final ForumBodyParagraphCache cache;
  final sessions = <ForumBodyTextPageSession>[];
  late final ForumBodyFlowSource source;

  ForumBodyParagraphLease pinForeign() {
    final document = const ForumBodyParser().parse(
      html: '<p>foreign</p>',
      sourceId: 'foreign',
      conversionIdentity: 'none',
    );
    final content = const ForumBodyParagraphContentBuilder().build(
      document: document,
      styles: const ForumBodyStyleResolver().resolve(document, _reader()),
      path: '0',
    );
    return cache.acquire(content: content, width: 100);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 40 && !ready(); frame++) {
    await tester.pump();
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets('source publishes immutable prefixes without mounting a body', (
    tester,
  ) async {
    final fixture = _Fixture(html: '<p>${'abcdefghij' * 40}</p>');
    final prefixes = <ForumBodyTextPageSnapshot>[];
    fixture.source.addListener(() {
      final prefix = fixture.source.prefix;
      if (prefix != null && prefix.isNotEmpty) prefixes.add(prefix);
    });
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(fixture.source.error, isNull);
    expect(prefixes.first.length, 1);
    expect(prefixes.last.isComplete, isTrue);
    expect(prefixes.last.length, greaterThan(1));
    expect(prefixes.last[0], same(prefixes.first[0]));
    expect(prefixes.first.length, 1);
    expect(find.byType(ForumBodyFlowBox), findsNothing);
    fixture.source.close();
    expect(fixture.sessions.every((s) => s.isClosed), isTrue);
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.cache.isClosed, isFalse);
  });

  testWidgets('adopting a running source replaces only its listener', (
    tester,
  ) async {
    final fixture = _Fixture(
      html: List.generate(200, (i) => '<p>paragraph $i</p>').join(),
    );
    var originalPublications = 0, replacementPublications = 0;
    void original() => originalPublications++;
    fixture.source.addListener(original);
    fixture.source.start();
    await _until(tester, () => fixture.source.prefix?.isNotEmpty == true);
    final first = fixture.source.prefix!;
    expect(first.isComplete, isFalse);
    final count = originalPublications;
    fixture.source.removeListener(original);
    fixture.source.addListener(() => replacementPublications++);
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(fixture.sessions, hasLength(1));
    expect(fixture.source.prefix!.isComplete, isTrue);
    expect(fixture.source.prefix![0], same(first[0]));
    expect(originalPublications, count);
    expect(replacementPublications, greaterThan(0));
  });

  testWidgets('close during publication retires queued work and native owner', (
    tester,
  ) async {
    final fixture = _Fixture(html: '<p>${'abcdefghij' * 40}</p>');
    var publications = 0;
    fixture.source.addListener(() {
      publications++;
      fixture.source.close();
    });
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(publications, 1);
    expect(fixture.source.isClosed, isTrue);
    expect(fixture.sessions.single.isClosed, isTrue);
    expect(fixture.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopping source work preserves an already published view', (
    tester,
  ) async {
    final fixture = _Fixture(html: '<p>${'abcdefghij' * 40}</p>');
    fixture.source.addListener(() {
      if (fixture.source.prefix?.isNotEmpty == true) fixture.source.stop();
    });
    fixture.source.start();
    await tester.pumpAndSettle();
    final prefix = fixture.source.prefix!;
    expect(prefix.length, 1);
    expect(prefix.isComplete, isFalse);
    expect(fixture.source.isStopped, isTrue);
    expect(fixture.sessions.single.isClosed, isFalse);
    final fragments = fixture.sessions.single.preparePageFragments(0);
    expect(fragments, isNotEmpty);
    for (final fragment in fragments) {
      fragment.close();
    }
    expect(fixture.source.start, throwsStateError);
    expect(fixture.source.prefix, same(prefix));
  });

  testWidgets('compact probe publishes only the final resolved width', (
    tester,
  ) async {
    final fixture = _Fixture(compactMinWidth: 20);
    final widths = <double>[];
    fixture.source.addListener(() => widths.add(fixture.source.prefix!.width));
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(fixture.source.error, isNull);
    expect(fixture.sessions, hasLength(2));
    expect(fixture.sessions.first.isClosed, isTrue);
    expect(widths, isNotEmpty);
    expect(widths.every((w) => w >= 20 && w < 100), isTrue);
    expect(widths.toSet(), hasLength(1));
  });

  for (final retire in [false, true]) {
    testWidgets('pinned budget release resumes only a live source ($retire)', (
      tester,
    ) async {
      final fixture = _Fixture(cacheEntries: 1);
      final foreign = fixture.pinForeign();
      addTearDown(foreign.release);
      var publications = 0;
      fixture.source.addListener(() => publications++);
      fixture.source.start();
      await _until(
        tester,
        () => fixture.sessions.single.waitingForLayoutBudget,
      );
      expect(fixture.source.prefix?.isEmpty, isTrue);
      final beforeRelease = publications;
      if (retire) fixture.source.close();
      foreign.release();
      await tester.pumpAndSettle();
      if (retire) {
        expect(publications, beforeRelease);
        expect(fixture.sessions.single.isClosed, isTrue);
      } else {
        expect(fixture.source.prefix!.isComplete, isTrue);
        expect(publications, greaterThan(0));
      }
      expect(fixture.source.error, isNull);
      expect(fixture.cache.activeLeases, 0);
    });
  }

  testWidgets('late source failure keeps its accepted prefix until close', (
    tester,
  ) async {
    final fixture = _Fixture(html: '<p>${'abcdefghij' * 40}</p>', maxPages: 1);
    ForumBodyTextPageSnapshot? accepted;
    fixture.source.addListener(() {
      final prefix = fixture.source.prefix;
      if (prefix?.isNotEmpty == true) accepted ??= prefix;
    });
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(fixture.source.error, isA<ForumBodyTextPageException>());
    expect(fixture.source.errorStack, isNotNull);
    expect(accepted, isNotNull);
    expect(fixture.source.prefix, same(accepted));
    expect(accepted!.length, 1);
    expect(fixture.sessions.single.isClosed, isFalse);
    fixture.source.close();
    expect(fixture.sessions.single.isClosed, isTrue);
  });

  for (final retireCache in [false, true]) {
    testWidgets(
      'owner retirement wakes a budget-blocked source ($retireCache)',
      (tester) async {
        final fixture = _Fixture(cacheEntries: 1);
        final foreign = fixture.pinForeign();
        addTearDown(foreign.release);
        fixture.source.start();
        await _until(
          tester,
          () => fixture.sessions.single.waitingForLayoutBudget,
        );
        if (retireCache) {
          fixture.cache.close();
        } else {
          fixture.sessions.single.close();
        }
        await tester.pumpAndSettle();
        expect(
          fixture.source.error,
          isA<ForumBodyTextPageSessionException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSessionFailure.ownerRetired,
          ),
        );
        final builds = fixture.cache.layoutBuildCount;
        foreign.release();
        await tester.pumpAndSettle();
        expect(fixture.cache.layoutBuildCount, builds);
      },
    );
  }

  testWidgets('factory failure can close its owner during error publication', (
    tester,
  ) async {
    final failure = StateError('factory retired');
    late final ForumBodyFlowSource source;
    source = ForumBodyFlowSource(
      width: 100,
      openSession: (_, {required probe}) => throw failure,
    );
    var publications = 0;
    source.addListener(() {
      publications++;
      source.close();
    });
    source.start();
    await tester.pumpAndSettle();
    expect(source.error, same(failure));
    expect(source.isClosed, isTrue);
    expect(publications, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retirement inside the factory closes its unaccepted session', (
    tester,
  ) async {
    late final _Fixture fixture;
    fixture = _Fixture(onOpen: () => fixture.source.close());
    fixture.source.start();
    await tester.pumpAndSettle();
    expect(fixture.source.isClosed, isTrue);
    expect(fixture.source.prefix, isNull);
    expect(fixture.sessions.single.isClosed, isTrue);
    expect(fixture.cache.activeLeases, 0);
    expect(tester.takeException(), isNull);
  });
}
