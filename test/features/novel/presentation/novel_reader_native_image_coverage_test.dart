import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_coverage.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_image_resources.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_coverage_cursor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_prefix_verifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_hint_search.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_table_anchor_probe.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_view_window.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';

import '../test_support/native_reader_image_test_host.dart';

final class _Fixture {
  _Fixture(String html) {
    final semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    final body = const ForumBodyParser().parse(
      html: html,
      sourceId: 'episode',
      conversionIdentity: 'none',
    );
    chapter = NovelReaderNativePreparedChapter(
      episodeId: 'episode',
      convertedTextNodeCount: 0,
      document: body,
      anchors: const NovelReaderNativeAnchorBinder().bind(
        episodeId: 'episode',
        sourceId: 'episode',
        semanticDocument: semantic,
        bodyDocument: body,
      ),
    );
    addTearDown(cache.close);
  }
  late final NovelReaderNativePreparedChapter chapter;
  final cache = ForumBodyParagraphCache(
    maxEntries: 16,
    maxEstimatedBytes: 1 << 22,
  );
  ForumBodyTextPageSession session({
    double ratio = 1,
    double height = 100,
    double width = 100,
    bool inline = false,
    bool dedicatedTables = false,
    Size imageSize = const Size(20, 10),
    NativeReaderImageTestHost? imageHost,
  }) {
    final host = imageHost ?? NativeReaderImageTestHost(aspectRatio: ratio);
    final resources = NovelReaderNativeImageResources(
      chapter: chapter,
      host: host,
      policy: host,
    );
    final session = ForumBodyTextPageSession(
      document: chapter.document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
        paragraphAfter: 0,
      ),
      cache: cache,
      layoutId: 'images-$ratio',
      width: width,
      height: height,
      dedicatedTables: dedicatedTables,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 100,
        maxParagraphs: 100,
        maxTextCodeUnits: 20000,
        maxRuns: 100,
        maxIssuedLeases: 32,
      ),
      imageResolver: resources.resolve,
      inlineImageResolver: !inline
          ? null
          : (identity, element, style) {
              final input = resources.resolve(identity, element);
              if (input == null) return null;
              final image = host.resolveImage(
                url: Uri.parse(input.entry.url),
                imageIndex: input.entry.index,
                isSticker: false,
                htmlSize:
                    element.resource!.width != null &&
                        element.resource!.height != null
                    ? Size(element.resource!.width!, element.resource!.height!)
                    : null,
              )!;
              return ForumBodyInlineImageInput(
                document: chapter.document,
                element: element,
                image: image,
                entry: input.entry,
                dimensions: PlaceholderDimensions(
                  size: imageSize,
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  baselineOffset: imageSize.height,
                ),
              );
            },
    );
    addTearDown(session.close);
    while (!session.isComplete) {
      session.advance(maxEvents: 1, maxLines: 1);
    }
    return session;
  }

  List<ForumBodyPreparedTextFragment> prepare(
    ForumBodyTextPageSession session, {
    int page = 0,
  }) {
    final job = session.openPagePreparation(page);
    while (!job.isReady) {
      job.advance(maxFragments: 1, maxParts: 1);
    }
    final values = job.takeFragments();
    job.close();
    return values;
  }
}

NovelReaderNativePageCoverage _coverage(
  _Fixture f,
  ForumBodyTextPageSession session,
  List<ForumBodyPreparedTextFragment> values, {
  int page = 0,
  Rect? viewportClip,
  NovelReaderNativeCoverageLimits limits =
      const NovelReaderNativeCoverageLimits(),
}) {
  final cursor = NovelReaderNativePageCoverageCursor.prepared(
    anchors: f.chapter.anchors,
    snapshot: session.snapshot,
    pageIndex: page,
    layoutId: session.snapshot.layoutId,
    fragments: values,
    viewportClip: viewportClip,
    limits: limits,
  );
  addTearDown(cursor.close);
  for (
    var i = 0;
    cursor.state == NovelReaderNativeCoverageState.active && i < 10000;
    i++
  ) {
    final step = cursor.advance(
      maxGraphemes: 1,
      maxFragments: 1,
      maxResources: 1,
    );
    expect(step.graphemesChecked, lessThanOrEqualTo(1));
    expect(step.resourcesChecked, lessThanOrEqualTo(1));
    expect(step.fragmentsCompleted, lessThanOrEqualTo(1));
    expect(step.madeProgress, isTrue);
  }
  return cursor.result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a table image is found by its original path and returns a cell reveal',
    () async {
      final fixture = _Fixture(
        '<p>before</p><table width="150"><tr>'
        '<td width="110">left</td>'
        '<td><img src="https://x/a.png" width="24" height="12"></td>'
        '</tr></table><p>after</p>',
      );
      final session = fixture.session(dedicatedTables: true);
      final anchor = fixture.chapter.anchors.images.single.anchor;
      final snapshot = session.snapshot;
      final hint = NovelReaderNativePageHintSearch(
        snapshot: snapshot,
        layoutId: snapshot.layoutId,
        anchors: fixture.chapter.anchors,
        anchor: anchor,
      );
      addTearDown(hint.close);
      hint.advance(maxPages: 8, maxFragments: 8);
      expect(hint.takeCandidates().single.pageIndex, 1);
      final token = NovelReaderPaginationCancellationToken();
      addTearDown(token.cancel);
      final result = await probeNovelReaderNativeTableAnchor(
        session: session,
        anchors: fixture.chapter.anchors,
        pageIndex: 1,
        target: anchor,
        allowNodeCompatibility: false,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
        token: token,
      );
      expect(result, isNotNull);
      expect(result!.anchor.nodeId, anchor.nodeId);
      expect(result.anchor.textIdentity, anchor.textIdentity);
      expect(result.bounds.left, greaterThanOrEqualTo(110));
      expect(result.bounds.width, 24);
      expect(fixture.cache.activeLeases, 0);
      expect(session.activeIssuedTablePages, 0);
    },
  );

  test('viewport clipping cannot prove an image from a partial frame', () {
    final fixture = _Fixture('<img src="https://x/a.png">');
    final session = fixture.session();
    final values = fixture.prepare(session);
    addTearDown(() {
      for (final fragment in values) {
        fragment.close();
      }
    });
    final fragment = session.snapshot.single.fragments.single;
    final bounds = fragment.imageFrame!.imageRect.shift(
      Offset(fragment.left, fragment.top),
    );
    final whole = _coverage(fixture, session, values, viewportClip: bounds);
    final partial = _coverage(
      fixture,
      session,
      values,
      viewportClip: Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.center.dy,
      ),
    );
    expect(whole.images, hasLength(1));
    expect(whole.hasClippedResources, isFalse);
    expect(partial.images, isEmpty);
    expect(partial.hasClippedResources, isTrue);
  });

  testWidgets('a mixed text page waits for every current inline image frame', (
    tester,
  ) async {
    final f = _Fixture(
      '<p>A<img src="https://x/a.png">B<img src="https://x/a.png">C</p>',
    );
    final host = NativeReaderImageTestHost();
    addTearDown(host.completeDimensions);
    final session = f.session(inline: true, imageHost: host);
    final lifetime = NovelReaderPaginationCancellationToken();
    addTearDown(lifetime.cancel);
    final controller = NovelReaderNativePagedController(
      session: session,
      anchors: f.chapter.anchors,
      paginationKey: 'mixed-inline-frames',
      parent: lifetime,
      position: const NovelReaderProgressSnapshot(
        novelId: 'novel',
        episodeId: 'episode',
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 0,
        progressPercent: 0,
        isProgressPercentValid: true,
      ),
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      performance: const NovelReaderPaginationPerformancePolicy(
        enforceBudgets: false,
      ),
      idleScheduler: () async {},
    );
    addTearDown(controller.close);
    final reports = <NovelReaderPaginationPosition>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            height: 100,
            child: NovelReaderNativePagedViewport(
              controller: controller,
              ownerIdentity: Object(),
              readingAuthorityIdentity: Object(),
              imageHost: host,
              onPositionChanged: reports.add,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; reports.isEmpty && i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(reports.last.isBodyEndVisible, isFalse);
    final initial = reports.last.anchor;
    host.callback(0).frame?.call();
    await tester.pump(const Duration(milliseconds: 20));
    expect(reports.last.isBodyEndVisible, isFalse);
    host.callback(1).frame?.call();
    for (var i = 0; !reports.last.isBodyEndVisible && i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(reports.last.isBodyEndVisible, isTrue);
    expect(reports.last.anchor.nodeId, initial.nodeId);
    expect(reports.last.anchor.textOffset, initial.textOffset);
    expect(reports.last.hasUserNavigated, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(session.activeIssuedImages, 0);
    expect(f.cache.activeLeases, 0);
  });

  for (final version in [1, 37]) {
    testWidgets(
      'inline image restore and current frames keep authority format=$version',
      (tester) async {
        final f = _Fixture(
          '<p><img src="https://x/a.png"><img src="https://x/a.png"><img src="https://x/a.png"></p>',
        );
        final host = NativeReaderImageTestHost();
        addTearDown(host.completeDimensions);
        final session = f.session(
          inline: true,
          width: 30,
          height: 20,
          imageHost: host,
        );
        final source = f.chapter.anchors.images.last.anchor;
        final lifetime = NovelReaderPaginationCancellationToken();
        addTearDown(lifetime.cancel);
        final controller = NovelReaderNativePagedController(
          session: session,
          anchors: f.chapter.anchors,
          paginationKey: 'inline-restore',
          parent: lifetime,
          position: NovelReaderProgressSnapshot(
            novelId: 'novel',
            episodeId: 'episode',
            flowMode: NovelReaderFlowMode.pagedLtr,
            scrollOffset: 0,
            pageIndex: 99,
            pageCount: 200,
            progressPercent: .8,
            isProgressPercentValid: true,
            anchorNodeId: source.nodeId,
            anchorTextOffset: version == 1 ? 0 : -3,
            anchorFormatVersion: version,
            anchorTextIdentity: source.textIdentity,
          ),
          scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
          performance: const NovelReaderPaginationPerformancePolicy(
            enforceBudgets: false,
          ),
          windowLimits: const NovelReaderNativeViewWindowLimits(radius: 0),
          idleScheduler: () async {},
        );
        addTearDown(controller.close);
        final reports = <NovelReaderPaginationPosition>[];
        final owner = Object(), authority = Object();
        Widget widget(NativeReaderImageTestHost imageHost) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 30,
              height: 20,
              child: NovelReaderNativePagedViewport(
                controller: controller,
                ownerIdentity: owner,
                readingAuthorityIdentity: authority,
                imageHost: imageHost,
                onPositionChanged: reports.add,
              ),
            ),
          ),
        );
        await tester.pumpWidget(widget(host));
        for (var i = 0; reports.isEmpty && i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(controller.error, isNull);
        expect(reports.last.pageIndex, 2);
        expect(reports.last.anchor.nodeId, source.nodeId);
        expect(reports.last.isReadOnlyCompatibilityRestore, version != 1);
        expect(reports.last.hasUserNavigated, isFalse);
        expect(reports.last.isBodyEndVisible, isFalse);
        final initial = reports.last;
        final old = host.callback(2);
        old.frame?.call();
        for (var i = 0; !reports.last.isBodyEndVisible && i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(reports.last.isBodyEndVisible, isTrue);
        expect(reports.last.isReadOnlyCompatibilityRestore, version != 1);
        expect(reports.last.hasUserNavigated, isFalse);
        expect(reports.last.anchor.nodeId, initial.anchor.nodeId);
        final next = NativeReaderImageTestHost();
        addTearDown(next.completeDimensions);
        await tester.pumpWidget(widget(next));
        await tester.pump(const Duration(milliseconds: 20));
        expect(reports.last.isBodyEndVisible, isFalse);
        old.frame?.call();
        await tester.pump(const Duration(milliseconds: 20));
        expect(reports.last.isBodyEndVisible, isFalse);
        next.callback(2).frame?.call();
        for (var i = 0; !reports.last.isBodyEndVisible && i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(reports.last.isBodyEndVisible, isTrue);
        expect(reports.last.hasUserNavigated, isFalse);
        expect(reports.last.isReadOnlyCompatibilityRestore, version != 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(session.activeIssuedImages, 0);
        expect(f.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('inline coverage merges actual image fences with adjacent text in source order', () {
    final f = _Fixture(
      '<p><img src="https://x/a.png">A<img src="https://x/a.png">B<img src="https://x/a.png"></p>',
    );
    final session = f.session(inline: true);
    final values = f.prepare(session);
    final coverage = _coverage(f, session, values);
    expect(coverage.images.map((i) => i.inlineAtomIndex), [0, 1, 2]);
    expect(coverage.images.map((i) => i.parentDisplayFenceUtf16), [0, 1, 2]);
    expect(
      coverage.locations.map(
        (location) => location is NovelReaderNativeImageCoverage
            ? 'I${location.imageIndex}'
            : 'T${location.displayUtf16}:${location.affinity.name}',
      ),
      [
        'I0',
        'T0:downstream',
        'T1:upstream',
        'I1',
        'T1:downstream',
        'T2:upstream',
        'I2',
      ],
    );
    expect(coverage.hasClippedResources, isFalse);
    for (final image in f.chapter.anchors.images) {
      final location =
          coverage.locate(image.anchor)! as NovelReaderNativeImageCoverage;
      expect(location.sourceRune, isNull);
      expect(location.displayUtf16, isNull);
      expect(
        location.rect,
        (values.single as ForumBodyPreparedInlineFragment)
            .view
            .images[location.inlineAtomIndex]!
            .rect,
      );
    }
    values.single.close();
    expect(f.cache.activeLeases, 0);
  });

  test('resource-only inline pages identify only their actual image node', () {
    final f = _Fixture(
      '<p><img src="https://x/a.png"><img src="https://x/a.png"><img src="https://x/a.png"></p>',
    );
    final session = f.session(inline: true, width: 30, height: 20);
    expect(session.snapshot, hasLength(3));
    for (var i = 0; i < 3; i++) {
      final values = f.prepare(session, page: i);
      final coverage = _coverage(
        f,
        session,
        values,
        page: i,
        limits: const NovelReaderNativeCoverageLimits(
          maxGraphemes: 0,
          maxResources: 1,
        ),
      );
      expect(coverage.points, isEmpty);
      expect(coverage.images.single.imageIndex, i);
      expect(coverage.images.single.parentDisplayFenceUtf16, 0);
      for (var other = 0; other < 3; other++) {
        expect(
          coverage.locate(f.chapter.anchors.images[other].anchor) != null,
          other == i,
        );
      }
      values.single.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  test('inline resource work has independent per-step and total budgets', () {
    final f = _Fixture(
      '<p><img src="https://x/a.png"><img src="https://x/a.png"><img src="https://x/a.png"></p>',
    );
    final session = f.session(inline: true);
    final values = f.prepare(session);
    final cursor = NovelReaderNativePageCoverageCursor.prepared(
      anchors: f.chapter.anchors,
      snapshot: session.snapshot,
      pageIndex: 0,
      layoutId: session.snapshot.layoutId,
      fragments: values,
      limits: const NovelReaderNativeCoverageLimits(
        maxGraphemes: 0,
        maxResources: 2,
      ),
    );
    addTearDown(cursor.close);
    for (var i = 0; i < 2; i++) {
      final step = cursor.advance(
        maxGraphemes: 1,
        maxFragments: 1,
        maxResources: 1,
      );
      expect(step.resourcesChecked, 1);
      expect(step.graphemesChecked, 0);
      expect(step.fragmentsCompleted, 0);
      expect(step.madeProgress, isTrue);
    }
    expect(
      () => cursor.advance(maxGraphemes: 1, maxFragments: 1, maxResources: 1),
      throwsA(
        isA<NovelReaderNativeCoverageException>().having(
          (e) => e.failure,
          'failure',
          NovelReaderNativeCoverageFailure.budget,
        ),
      ),
    );
    expect(cursor.state, NovelReaderNativeCoverageState.failed);
    expect(values.single.isActive, isTrue);
    values.single.close();
  });

  test('retirement between cooperative resource steps never publishes partial proof', () {
    final f = _Fixture(
      '<p><img src="https://x/a.png"><img src="https://x/a.png"></p>',
    );
    final session = f.session(inline: true);
    final values = f.prepare(session);
    final cursor = NovelReaderNativePageCoverageCursor.prepared(
      anchors: f.chapter.anchors,
      snapshot: session.snapshot,
      pageIndex: 0,
      layoutId: session.snapshot.layoutId,
      fragments: values,
    );
    addTearDown(cursor.close);
    expect(
      cursor
          .advance(maxGraphemes: 1, maxFragments: 1, maxResources: 1)
          .resourcesChecked,
      1,
    );
    values.single.close();
    expect(
      () => cursor.advance(maxGraphemes: 1, maxFragments: 1, maxResources: 1),
      throwsA(
        isA<NovelReaderNativeCoverageException>().having(
          (e) => e.failure,
          'failure',
          NovelReaderNativeCoverageFailure.retired,
        ),
      ),
    );
    expect(() => cursor.result, throwsStateError);
  });
  test(
    'real image coverage uses fragment budget and no glyph/source coordinates',
    () {
      final f = _Fixture(
        '<img src="https://x/a.png"><img src="https://x/a.png">',
      );
      final session = f.session(ratio: 10);
      final values = f.prepare(session);
      final cursor = NovelReaderNativePageCoverageCursor.prepared(
        anchors: f.chapter.anchors,
        snapshot: session.snapshot,
        pageIndex: 0,
        layoutId: session.snapshot.layoutId,
        fragments: values,
        limits: const NovelReaderNativeCoverageLimits(
          maxGraphemes: 0,
          maxPoints: 2,
        ),
      );
      final first = cursor.advance(maxFragments: 1, maxGraphemes: 1);
      expect(first.fragmentsCompleted, 1);
      expect(first.graphemesChecked, 0);
      expect(first.isComplete, isFalse);
      cursor.advance(maxFragments: 1, maxGraphemes: 1);
      final coverage = cursor.result;
      expect(coverage.points, isEmpty);
      expect(coverage.images.map((p) => p.path), ['0', '1']);
      expect(coverage.locationCount, 2);
      expect(coverage.hasClippedResources, isFalse);
      for (final image in f.chapter.anchors.images) {
        final point = coverage.locate(image.anchor)!;
        expect(point.sourceRune, isNull);
        expect(point.displayUtf16, isNull);
        expect(point.fragmentIndex, image.imageIndex);
      }
      expect(f.cache.layoutBuildCount, 0);
      final tiny = NovelReaderNativePageCoverageCursor.prepared(
        anchors: f.chapter.anchors,
        snapshot: session.snapshot,
        pageIndex: 0,
        layoutId: session.snapshot.layoutId,
        fragments: values,
        limits: const NovelReaderNativeCoverageLimits(maxPoints: 1),
      );
      expect(
        () => tiny.advance(maxFragments: 2, maxGraphemes: 1),
        throwsA(isA<NovelReaderNativeCoverageException>()),
      );
      for (final value in values) {
        value.close();
      }
    },
  );

  test('source and image coverage merge in actual rendered fragment order', () {
    final f = _Fixture(
      '<img src="https://x/a.png"><p>A</p><img src="https://x/a.png">',
    );
    final session = f.session(ratio: 10);
    final values = f.prepare(session);
    final cursor = NovelReaderNativePageCoverageCursor.prepared(
      anchors: f.chapter.anchors,
      snapshot: session.snapshot,
      pageIndex: 0,
      layoutId: session.snapshot.layoutId,
      fragments: values,
    );
    while (cursor.state == NovelReaderNativeCoverageState.active) {
      cursor.advance(maxFragments: 1, maxGraphemes: 1);
    }
    expect(cursor.result.locations.map((e) => e.fragmentIndex), [0, 1, 1, 2]);
    expect(cursor.result.locations.first.anchor.nodeId, 'node-0');
    expect(cursor.result.images, hasLength(2));
    expect(cursor.result.points, hasLength(2));
    for (final value in values) {
      value.close();
    }
  });

  test('retry compares real image rectangles even when outer page geometry is equal', () {
    final f = _Fixture('<img src="https://x/a.png">');
    final original = f.session(ratio: .1),
        equal = f.session(ratio: .1),
        changed = f.session(ratio: .2);
    for (final (other, expected) in [
      (equal, NovelReaderNativePrefixState.matched),
      (changed, NovelReaderNativePrefixState.mismatched),
    ]) {
      final verifier = NovelReaderNativePrefixVerifier(
        previous: original.snapshot,
        previousPaginationKey: 'same',
        incoming: other.snapshot,
        incomingPaginationKey: 'same',
      );
      verifier.advance(maxPages: 1, maxFragments: 1);
      expect(verifier.state, expected);
      verifier.close();
    }
  });
}
