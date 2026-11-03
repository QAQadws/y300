import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

const _body =
    'ffi e<b>́</b> 日本語 <span style="font-size:31px;'
    'text-emphasis-position:under">مرحبا</span> 👩‍👩‍👧‍👦';

final class _Fixture {
  _Fixture({
    String body = _body,
    String? html,
    int entries = 16,
    this.width = 100,
    this.scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
  }) {
    document = const ForumBodyParser().parse(
      html:
          html ??
          '<div class="pstatus" style="margin:0;text-emphasis:\'X\' red">$body</div>',
      sourceId: 'fitted-emphasis',
      conversionIdentity: 'none',
    );
    reader = ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff123456),
      ),
      fontRevision: 'fitted-ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
      paragraphBefore: 0,
      paragraphAfter: 0,
    );
    cache = ForumBodyParagraphCache(
      maxEntries: entries,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    session = open();
  }
  final double width;
  final TextScaler scaler;
  late final ForumBodyDocument document;
  late final ForumBodyReaderStyle reader;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  ForumBodyTextPageSession open({
    int? pageEntries,
    int? pageBytes,
    String id = 'fitted-layout',
  }) {
    final value = ForumBodyTextPageSession(
      document: document,
      reader: reader,
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 200000,
        maxRuns: 20000,
        maxIssuedLeases: 64,
      ),
      layoutId: id,
      width: width,
      height: 300,
      textScaler: scaler,
      maxNativeEntriesPerPage: pageEntries,
      maxNativeEstimatedBytesPerPage: pageBytes,
    );
    addTearDown(value.close);
    return value;
  }

  ForumBodyTextPageSessionStep step([ForumBodyTextPageSession? input]) {
    final pictures = cache.pictureBuildCount;
    final result = (input ?? session).advance(
      maxEvents: 2,
      maxLines: 1,
      maxFormatParts: 1,
    );
    expect(result.formatUnitsPrepared, lessThanOrEqualTo(1));
    expect(result.layoutsBuilt, lessThanOrEqualTo(1));
    expect(result.pagesPublished, lessThanOrEqualTo(1));
    expect(result.linesInspected, lessThanOrEqualTo(1));
    expect(result.flowWorkDone, lessThanOrEqualTo(2));
    expect(cache.pictureBuildCount, pictures);
    return result;
  }

  void finish([ForumBodyTextPageSession? input]) {
    final current = input ?? session;
    for (var n = 0; !current.isComplete; n++) {
      if (n > 50000) fail('Session did not finish');
      final s = step(current);
      expect(s.waitingForLayoutBudget, isFalse);
      expect(s.madeProgress, isTrue);
    }
  }

  ForumBodyTextPagePreparation prepare() => session.openPagePreparation(0);
  List<ForumBodyPreparedTextFragment> deliver([
    ForumBodyTextPagePreparation? input,
  ]) {
    final work = input ?? prepare();
    addTearDown(work.close);
    for (var n = 0; !work.isReady; n++) {
      if (n > 50000) fail('Page did not finish');
      final before = cache.layoutBuildCount + cache.pictureBuildCount;
      final step = work.advance(maxFragments: 1, maxParts: 1);
      expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
      expect(
        cache.layoutBuildCount + cache.pictureBuildCount - before,
        lessThanOrEqualTo(1),
      );
    }
    final result = work.takeFragments();
    work.close();
    addTearDown(() {
      for (final binding in result) {
        binding.close();
      }
    });
    validateForumBodyPreparedTextPageBinding(
      snapshot: session.snapshot,
      pageIndex: 0,
      layoutId: session.snapshot.layoutId,
      fragments: result,
    );
    return result;
  }

  ForumBodyParagraphLease pin(double width) {
    final content = const ForumBodyParagraphContentBuilder().build(
      document: document,
      path: '0',
      styles: const ForumBodyStyleResolver().resolve(document, reader),
    );
    final source = ForumBodyEmphasisGlyphPreparation(content: content);
    while (!source.isReady) {
      source.advance(maxParts: 1);
    }
    final lease = cache.acquire(
      content: source.takeInput().glyphs,
      width: width,
    );
    addTearDown(lease.release);
    return lease;
  }
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual per-size samples');
}

Widget _surface(
  _Fixture fixture,
  List<ForumBodyPreparedTextFragment> bindings, {
  void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)? onTap,
}) => Directionality(
  textDirection: fixture.reader.textDirection,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: fixture.width,
      height: 300,
      child: RepaintBoundary(
        key: const ValueKey('raster'),
        child: ForumBodyTextPageSurface.prepared(
          snapshot: fixture.session.snapshot,
          pageIndex: 0,
          layoutId: fixture.session.snapshot.layoutId,
          fragments: bindings,
          onSourceTap: onTap,
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final direction in TextDirection.values) {
    for (final width in [8.0, 80.0, 600.0]) {
      for (final nonlinear in [false, true]) {
        test(
          'actual edit status fit is shared by text/marks/source: $direction $width $nonlinear',
          () {
            final fixture = _Fixture(
              width: width,
              direction: direction,
              scaler: nonlinear ? const _Nonlinear() : TextScaler.noScaling,
            );
            fixture.finish();
            expect(fixture.cache.activeLeases, 0);
            fixture.cache.clearUnpinned();
            final bindings = fixture.deliver();
            final fitted =
                    bindings.single as ForumBodyPreparedFittedEmphasisFragment,
                view = fitted.view;
            final f = fixture.session.snapshot.single.fragments.single;
            expect(f.kind, ForumBodyTextPageFragmentKind.fittedEmphasis);
            expect(view.width, width);
            expect(
              view.input.content.layoutMode,
              ForumBodyParagraphLayoutMode.fitSingleLine,
            );
            expect(view.projection.text, 'ffi é 日本語 مرحبا 👩‍👩‍👧‍👦');
            expect(f.coverageStartUtf16, 0);
            expect(f.coverageEndUtf16, view.projection.text.length);
            expect(f.startLine, 0);
            expect(f.endLine, 1);
            expect(f.height, view.height);
            expect(fitted.lines.single.top, 0);
            expect(fitted.lines.single.bottom, view.height);
            final native =
                (view.nativeLeases.first as ForumBodyParagraphLease).layout;
            expect(view.marks, isNotEmpty);
            expect(
              view.marks.every((m) => m.fitScale == native.paintScale),
              isTrue,
            );
            expect(native.paintScale, width < 600 ? lessThan(1) : 1);
            for (final box in fitted.glyphBoxes(
              0,
              view.projection.text.length,
            )) {
              expect(box.top, greaterThanOrEqualTo(0));
              expect(box.bottom, lessThanOrEqualTo(view.height));
              final hit = view.sourceAt(box.toRect().center);
              expect(
                hit.displayUtf16,
                inInclusiveRange(0, view.projection.text.length),
              );
            }
            expect(
              () => fixture.session.preparePageLeases(0),
              throwsStateError,
            );
            final before =
                fixture.cache.layoutBuildCount +
                fixture.cache.pictureBuildCount;
            final warm = fixture.session.preparePageFragments(0);
            expect(
              fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
              before,
            );
            expect(
              warm.single.nativeLeases.last.nativeInputIdentity,
              view.nativeLeases.last.nativeInputIdentity,
            );
            expect(fixture.cache.activeLeases, 4);
            bindings.single.close();
            expect(warm.single.isActive, isTrue);
            expect(fixture.cache.activeLeases, 2);
            warm.single.close();
            expect(fixture.cache.activeLeases, 0);
          },
        );
      }
    }
  }

  test('BR normalization and original source survive the fitted format', () {
    final fixture = _Fixture(body: 'A<br><span>B</span><br>C');
    fixture.finish();
    final binding =
        fixture.deliver().single as ForumBodyPreparedFittedEmphasisFragment;
    expect(binding.projection.text, 'A B C');
    expect(fixture.document.sourceText, 'A\nB\nC');
    expect(binding.projection.sourceAtUtf16(4).sourceRune, 4);
    expect(binding.glyphBoxes(4, 5), isNotEmpty);
  });

  test('fitted cold cached-only miss can resume the same bounded page job', () {
    final fixture = _Fixture(body: 'ABC');
    fixture.finish();
    fixture.cache.clearUnpinned();
    final job = fixture.prepare();
    final before =
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
    var inspected = 0;
    for (var n = 0; !job.cacheMiss; n++) {
      if (n > 10000) fail('Expected a cached-only miss');
      expect(job.tryPrepareCached(maxParts: 1), isFalse);
      inspected++;
      expect(
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
        before,
      );
    }
    expect(inspected, greaterThan(job.expectedNativeLeaseCount));
    expect(job.expectedNativeLeaseCount, 2);
    expect(
      fixture.deliver(job).single,
      isA<ForumBodyPreparedFittedEmphasisFragment>(),
    );
  });

  test('foreign pins also keep the same visible fitted page job resumable', () {
    final fixture = _Fixture(body: 'ABC', entries: 3);
    fixture.finish();
    fixture.cache.clearUnpinned();
    final pins = [fixture.pin(1), fixture.pin(2)], job = fixture.prepare();
    for (var n = 0; !job.waitingForLayoutBudget; n++) {
      if (n > 10000) fail('Expected a visible foreign-pin wait');
      job.advance(maxFragments: 1, maxParts: 1);
    }
    final before =
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
    for (var n = 0; n < 3; n++) {
      expect(
        job.advance(maxFragments: 1, maxParts: 1).waitingForLayoutBudget,
        isTrue,
      );
      expect(
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
        before,
      );
    }
    for (final pin in pins) {
      pin.release();
    }
    expect(fixture.deliver(job).single.isActive, isTrue);
  });

  test('two fitted contexts fail whole-page admission before acquiring either', () {
    final fixture = _Fixture(
      entries: 4,
      html:
          '<div class="pstatus" style="margin:0;text-emphasis:\'X\' red">ABC</div>'
          '<div class="pstatus" style="margin:0;text-emphasis:\'X\' red">DEF</div>',
    );
    fixture.finish();
    fixture.cache.clearUnpinned();
    final before =
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
    final job = fixture.prepare();
    expect(
      () => fixture.deliver(job),
      throwsA(
        isA<ForumBodyTextPagePreparationException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTextPagePreparationFailure.intrinsicBudget,
        ),
      ),
    );
    expect(
      fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
      before,
    );
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.session.reservedViewLeases, 0);
  });

  test(
    'a complete page combines ordinary, fitted, wrapping emphasis and ruby',
    () {
      final fixture = _Fixture(
        width: 140,
        html:
            '<p style="margin:0">before</p>'
            '<div class="pstatus" style="margin:0;text-emphasis:\'X\' red">ABC</div>'
            '<p style="margin:0;text-emphasis:\'X\' red">DEF</p>'
            '<p style="margin:0">R<ruby>G<rt>g</rt></ruby>S</p>',
      );
      fixture.finish();
      expect(fixture.session.snapshot.single.fragments.map((f) => f.kind), [
        ForumBodyTextPageFragmentKind.paragraph,
        ForumBodyTextPageFragmentKind.fittedEmphasis,
        ForumBodyTextPageFragmentKind.emphasis,
        ForumBodyTextPageFragmentKind.inline,
      ]);
      final bindings = fixture.deliver();
      expect(bindings, hasLength(4));
      fixture.session.close();
      expect(bindings.every((b) => !b.isActive), isTrue);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'closing the reader after ready prevents fitted transfer and drains reservation',
    () {
      final fixture = _Fixture(body: 'ABC');
      fixture.finish();
      final job = fixture.prepare();
      while (!job.isReady) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      expect(fixture.cache.activeLeases, 2);
      fixture.session.close();
      expect(job.takeFragments, throwsStateError);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test('foreign pins keep exact fitted numeric admission resumable', () {
    final fixture = _Fixture(body: 'ABC', entries: 3);
    final pins = [fixture.pin(1), fixture.pin(2)];
    for (var n = 0; !fixture.session.waitingForLayoutBudget; n++) {
      if (n > 10000) fail('Expected a foreign-pin wait');
      fixture.step();
    }
    final builds = fixture.cache.layoutBuildCount,
        nodes = fixture.session.resolvedNodeCount;
    for (var n = 0; n < 3; n++) {
      expect(fixture.step().waitingForLayoutBudget, isTrue);
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.session.resolvedNodeCount, nodes);
    }
    for (final pin in pins) {
      pin.release();
    }
    fixture.finish();
    expect(fixture.session.resolvedNodeCount, nodes);
    expect(
      fixture.deliver().single,
      isA<ForumBodyPreparedFittedEmphasisFragment>(),
    );
    fixture.session.close();
    expect(fixture.cache.activeLeases, 0);
  });

  for (final quota in ['cache', 'entries', 'bytes']) {
    test('the exact fitted scene participates in $quota admission', () {
      final fixture = _Fixture(body: 'ABC', entries: quota == 'cache' ? 2 : 16);
      if (quota == 'cache') {
        expect(
          fixture.finish,
          throwsA(isA<ForumBodyParagraphBudgetException>()),
        );
      } else {
        fixture.finish();
        final binding =
            fixture.deliver().single as ForumBodyPreparedFittedEmphasisFragment;
        final plan = binding.plan;
        expect(plan.nativeCosts, hasLength(3));
        final fontBytes =
            plan.nativeCosts.fold<int>(
              0,
              (sum, cost) => sum + cost.estimatedBytes,
            ) -
            plan.metrics.pictureInput.estimatedBytes;
        binding.close();
        fixture.session.close();
        final pictures = fixture.cache.pictureBuildCount;
        final limited = fixture.open(
          pageEntries: quota == 'entries' ? 2 : null,
          pageBytes: quota == 'bytes' ? fontBytes : null,
          id: 'limited',
        );
        expect(
          () => fixture.finish(limited),
          throwsA(
            isA<ForumBodyTextPageException>().having(
              (e) => e.failure,
              'failure',
              quota == 'entries'
                  ? ForumBodyTextPageFailure.nativeEntryLimit
                  : ForumBodyTextPageFailure.nativeByteLimit,
            ),
          ),
        );
        expect(fixture.cache.pictureBuildCount, pictures);
      }
      expect(fixture.cache.activeLeases, 0);
    });
  }

  for (final retirement in ['page', 'session', 'cache']) {
    test('recording retirement drains a fitted page: $retirement', () {
      final fixture = _Fixture(body: 'ABC');
      fixture.finish();
      final job = fixture.prepare();
      final previous = ui.Picture.onCreate;
      var calls = 0;
      ui.Picture.onCreate = (_) {
        if (++calls == 1) {
          if (retirement == 'cache') {
            fixture.cache.close();
          } else if (retirement == 'session') {
            fixture.session.close();
          } else {
            job.close();
          }
        }
      };
      try {
        expect(() => fixture.deliver(job), throwsA(anything));
      } finally {
        ui.Picture.onCreate = previous;
        job.close();
      }
      expect(calls, 1);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
    });
  }

  test(
    'fitted native tail SPACE stays in copying but cannot prove a glyph',
    () {
      final fixture = _Fixture(
        width: 30,
        html: '<p style="white-space:pre;text-emphasis:\'X\' red">AB  </p>',
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: fixture.document,
        path: '0',
        styles: const ForumBodyStyleResolver().resolve(
          fixture.document,
          fixture.reader,
        ),
        layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      );
      final source = ForumBodyEmphasisTextPreparation(content: content);
      while (!source.isReady) {
        source.advance(maxParts: 1);
      }
      final measured = ForumBodyEmphasisLineMetricsPreparation(
        input: source.takeInput(),
        cache: fixture.cache,
        ensureOwner: () {},
        width: 30,
      );
      while (!measured.isReady) {
        measured.advance(maxParts: 1);
      }
      final metrics = measured.takeMetrics();
      final planJob = ForumBodyFittedEmphasisPlanPreparation(
        metrics: metrics,
        cache: fixture.cache,
        ensureOwner: () {},
      );
      while (!planJob.isReady) {
        planJob.advance(maxParts: 1);
      }
      final plan = planJob.take();
      final visible = ForumBodyEmphasisLinePreparation.fromMetrics(
        input: metrics.input,
        metrics: metrics,
        cache: fixture.cache,
        ensureOwner: () {},
        width: 30,
        expectedTextScaler: TextScaler.noScaling,
      );
      while (!visible.isReady) {
        visible.advance(maxParts: 1);
      }
      final binding = ForumBodyPreparedTextFragment.fittedEmphasis(
        view: visible.takeLayout(),
        plan: plan,
      );
      addTearDown(binding.close);
      expect(binding.projection.text, 'AB  ');
      expect(
        (binding as ForumBodyPreparedFittedEmphasisFragment).view
            .selectionBoxes(2, 4),
        isNotEmpty,
      );
      expect(binding.glyphBoxes(2, 4), isEmpty);
      expect(binding.glyphBoxes(0, 2), isNotEmpty);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'fitted Widget replays, hits original text and omits hidden semantics: $direction',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final fixture = _Fixture(
            body: 'A<span style="visibility:hidden">ZZZ</span>B',
            direction: direction,
          );
          fixture.finish();
          final bindings = fixture.deliver();
          final fitted =
              bindings.single as ForumBodyPreparedFittedEmphasisFragment;
          final taps = <HtmlProjectedSourcePosition>[];
          final before =
              fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
          await tester.pumpWidget(
            _surface(fixture, bindings, onTap: (_, hit) => taps.add(hit)),
          );
          expect(tester.takeException(), isNull);
          expect(find.bySemanticsLabel('AB'), findsOneWidget);
          final box = fitted.glyphBoxes(4, 5).single.toRect();
          await tester.tapAt(
            tester.getTopLeft(find.byType(ForumBodyEmphasisLineSurface)) +
                box.center,
          );
          expect(taps.single.displayUtf16, inInclusiveRange(4, 5));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('raster')),
          );
          final alpha = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              for (var n = 3; n < bytes.length; n += 4) {
                if (bytes[n] != 0) return true;
              }
              return false;
            } finally {
              image.dispose();
            }
          });
          expect(alpha, isTrue);
          expect(
            fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
            before,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          expect(fixture.cache.activeLeases, 0);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'replacing a fitted binding retires a pending gesture without reacquiring',
    (tester) async {
      final fixture = _Fixture(body: 'ABC');
      fixture.finish();
      final first = fixture.deliver(), second = fixture.deliver();
      var taps = 0;
      final before =
          fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount;
      await tester.pumpWidget(
        _surface(fixture, first, onTap: (_, _) => taps++),
      );
      final origin = tester.getTopLeft(
        find.byType(ForumBodyEmphasisLineSurface),
      );
      final point = (first.single as ForumBodyPreparedFittedEmphasisFragment)
          .glyphBoxes(0, 1)
          .single
          .toRect()
          .center;
      final gesture = await tester.startGesture(origin + point);
      await tester.pumpWidget(
        _surface(fixture, second, onTap: (_, _) => taps++),
      );
      await gesture.up();
      expect(taps, 0);
      expect(fixture.cache.activeLeases, 2);
      await tester.tapAt(origin + point);
      expect(taps, 1);
      expect(
        fixture.cache.layoutBuildCount + fixture.cache.pictureBuildCount,
        before,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );
}
