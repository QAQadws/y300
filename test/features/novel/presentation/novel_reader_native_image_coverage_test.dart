import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_image_resources.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_coverage_cursor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_prefix_verifier.dart';

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
  ForumBodyTextPageSession session({double ratio = 1, double height = 100}) {
    final host = NativeReaderImageTestHost(aspectRatio: ratio);
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
      width: 100,
      height: height,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 100,
        maxParagraphs: 100,
        maxTextCodeUnits: 20000,
        maxRuns: 100,
        maxIssuedLeases: 32,
      ),
      imageResolver: resources.resolve,
    );
    addTearDown(session.close);
    while (!session.isComplete) {
      session.advance(maxEvents: 1, maxLines: 1);
    }
    return session;
  }

  List<ForumBodyPreparedTextFragment> prepare(
    ForumBodyTextPageSession session,
  ) {
    final job = session.openPagePreparation(0);
    while (!job.isReady) {
      job.advance(maxFragments: 1, maxParts: 1);
    }
    final values = job.takeFragments();
    job.close();
    return values;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
