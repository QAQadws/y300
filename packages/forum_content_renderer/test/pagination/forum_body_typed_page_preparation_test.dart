import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

final class Input {
  Input({int leases = 4, TextScaler textScaler = TextScaler.noScaling}) {
    session = ForumBodyTextPageSession(
      document: document,
      reader: reader,
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 10,
        maxFragments: 20,
        maxParagraphs: 10,
        maxTextCodeUnits: 100,
        maxRuns: 20,
        maxIssuedLeases: leases,
      ),
      layoutId: 'typed-preparation',
      width: 60,
      height: 40,
      textScaler: textScaler,
    );
    for (var n = 0; n < 100 && !session.isComplete; n++) {
      session.advance(maxEvents: 4, maxLines: 1);
    }
    expect(session.isComplete, isTrue);
  }
  final document = const ForumBodyParser().parse(
    html: '<p style="margin:0">A</p><p style="margin:0">B</p>',
    sourceId: 'typed-preparation',
    conversionIdentity: 'none',
  );
  final reader = ForumBodyReaderStyle(
    textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
    fontRevision: 'loaded',
    linkColor: const Color(0xff0000ff),
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: 4,
    maxEstimatedBytes: 1 << 20,
  );
  late final ForumBodyTextPageSession session;
  List<ForumBodyParagraphContent> get contents {
    final styles = const ForumBodyStyleResolver().resolve(document, reader);
    return [
      for (final path in ['0', '1'])
        const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: styles,
          path: path,
        ),
    ];
  }

  void close() {
    session.close();
    cache.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold existing preparation transfers typed fragments through its original reservation',
    () {
      final input = Input();
      addTearDown(input.close);
      input.cache.clearUnpinned();
      final prepare = input.session.openPagePreparation(0);
      expect(input.session.reservedViewLeases, 2);
      for (var n = 0; n < 10 && !prepare.isReady; n++) {
        final step = prepare.advance(maxFragments: 2);
        expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      }
      final fragments = prepare.takeFragments();
      expect(
        fragments,
        everyElement(isA<ForumBodyPreparedParagraphFragment>()),
      );
      expect(input.session.activeIssuedLeases, 2);
      expect(input.session.reservedViewLeases, 0);
      expect(prepare.state, ForumBodyTextPagePreparationState.transferred);
      expect(() => fragments.clear(), throwsUnsupportedError);
      prepare.close();
      expect(fragments.every((fragment) => fragment.isActive), isTrue);
      input.session.close();
      expect(fragments.every((fragment) => !fragment.isActive), isTrue);
      expect(input.cache.activeLeases, 0);
      expect(input.cache.isClosed, isFalse);
    },
  );

  testWidgets(
    'warm session typed convenience mounts the existing surface without native work',
    (tester) async {
      final input = Input();
      addTearDown(input.close);
      final builds = input.cache.layoutBuildCount;
      final fragments = input.session.preparePageFragments(0);
      final hits = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: input.session.snapshot,
              pageIndex: 0,
              layoutId: input.session.snapshot.layoutId,
              fragments: fragments,
              onSourceTap: (_, position) => hits.add(position.sourceRune),
            ),
          ),
        ),
      );
      final surfaces = find.byType(ForumBodyParagraphSurface);
      expect(surfaces, findsNWidgets(2));
      await tester.tapAt(
        tester.getTopLeft(surfaces.last) + const Offset(.1, 10),
      );
      expect(hits, [1]);
      expect(input.cache.layoutBuildCount, builds);
      expect(input.session.activeIssuedLeases, 2);
      await tester.pumpWidget(const SizedBox());
      expect(input.session.activeIssuedLeases, 0);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'ordinary and typed transfers share issued capacity and partial release accounting',
    () {
      final input = Input();
      addTearDown(input.close);
      final ordinary = input.session.openPagePreparation(0);
      final typed = input.session.openPagePreparation(0);
      expect(ordinary.tryPrepareCached(), isTrue);
      expect(typed.tryPrepareCached(), isTrue);
      expect(input.session.reservedViewLeases, 4);
      final leases = ordinary.takeLeases();
      final fragments = typed.takeFragments();
      expect(input.session.activeIssuedLeases, 4);
      leases.first.release();
      expect(input.session.activeIssuedLeases, 3);
      expect(
        () => input.session.openPagePreparation(0),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSessionFailure.leaseLimit,
          ),
        ),
      );
      leases.last.release();
      final pending = input.session.openPagePreparation(0);
      expect(input.session.reservedViewLeases, 2);
      pending.close();
      expect(input.session.reservedViewLeases, 0);
      for (final fragment in fragments) {
        fragment.close();
      }
      expect(input.session.activeIssuedLeases, 0);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'retirement during a cached miss is checked before returning no work',
    () {
      var closeOnScale = false;
      late Input input;
      final scaler = ClosingScaler(() {
        if (closeOnScale) input.session.close();
      });
      input = Input(textScaler: scaler);
      addTearDown(input.close);
      input.cache.clearUnpinned();
      final prepare = input.session.openPagePreparation(0);
      closeOnScale = true;
      expect(prepare.tryPrepareCached, throwsStateError);
      expect(prepare.state, ForumBodyTextPagePreparationState.closed);
      expect(input.session.reservedViewLeases, 0);
      expect(input.cache.activeLeases, 0);
      expect(input.cache.entryCount, 0);
    },
  );

  for (final closeOwner in [false, true]) {
    test(
      'retirement inside transfer cannot publish late typed handles (owner=$closeOwner)',
      () {
        final input = Input();
        addTearDown(input.close);
        var retired = 0;
        List<ForumBodyPreparedTextFragment>? rejected;
        final prepare = createForumBodyTextPagePreparation(
          cache: input.cache,
          snapshot: input.session.snapshot,
          pageIndex: 0,
          contents: input.contents,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
          onTransfer: (preparation, fragments) {
            rejected = fragments;
            if (closeOwner) {
              input.cache.close();
            } else {
              preparation.close();
            }
          },
          onRetire: (_) {
            retired++;
          },
        );
        expect(prepare.tryPrepareCached(), isTrue);
        expect(prepare.takeFragments, throwsStateError);
        expect(rejected, isNotNull);
        expect(rejected!.every((fragment) => !fragment.isActive), isTrue);
        expect(retired, 1);
        expect(input.cache.activeLeases, 0);
      },
    );
  }
}

final class ClosingScaler extends TextScaler {
  const ClosingScaler(this.onScale);
  final void Function() onScale;
  @override
  double scale(double fontSize) {
    onScale();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
