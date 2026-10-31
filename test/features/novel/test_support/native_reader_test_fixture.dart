import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_anchor_map.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

/// App-owned fixture: source provenance and actual native page/lease lifecycle.
final class NativeReaderTestFixture {
  NativeReaderTestFixture(
    String html, {
    int cacheEntries = 32,
    double width = 100,
    double height = 100,
    TextScaler textScaler = TextScaler.noScaling,
    bool complete = true,
    String layoutId = 'generation-a',
    ForumBodyParagraphCache? cacheOwner,
  }) {
    final semantic = const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    final body = const ForumBodyParser().parse(
      html: html.trim(),
      sourceId: 'source',
      conversionIdentity: 'none',
    );
    anchors = const NovelReaderNativeAnchorBinder().bind(
      episodeId: 'episode',
      sourceId: 'source',
      semanticDocument: semantic,
      bodyDocument: body,
    );
    cache =
        cacheOwner ??
        ForumBodyParagraphCache(
          maxEntries: cacheEntries,
          maxEstimatedBytes: 1 << 22,
        );
    session = ForumBodyTextPageSession(
      document: body,
      reader: _reader(),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 1000,
        maxTextCodeUnits: 20000,
        maxRuns: 10000,
        maxIssuedLeases: 128,
      ),
      layoutId: layoutId,
      width: width,
      height: height,
      textScaler: textScaler,
    );
    addTearDown(() {
      parent.cancel();
      session.close();
      if (cacheOwner == null) cache.close();
    });
    if (complete) finishSource();
  }
  late final NovelReaderNativeAnchorMap anchors;
  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  final parent = NovelReaderPaginationCancellationToken();

  void finishSource({int? pages}) {
    var calls = 0;
    while (!session.isComplete &&
        (pages == null || session.snapshot.length < pages)) {
      if (++calls > 10000) fail('Fixture source failed to finish');
      session.advance(maxEvents: 32, maxLines: 8);
    }
  }

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

  static ForumBodyReaderStyle _reader() => ForumBodyReaderStyle(
    textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
    fontRevision: 'ahem',
    linkColor: const Color(0xFF0000FF),
    paragraphAfter: 0,
  );
}
