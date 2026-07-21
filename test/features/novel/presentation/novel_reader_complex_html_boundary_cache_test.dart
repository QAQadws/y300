import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';

void main() {
  test(
    'coalesces builds and then serves the immutable boundary session',
    () async {
      final cache = NovelReaderComplexHtmlBoundaryCache(capacity: 2);
      const indexer = DefaultNovelReaderComplexHtmlBoundaryIndexer();
      final request = _request('<p>复杂分页正文。</p>');
      var buildCount = 0;

      final first = cache.resolve(
        request: request,
        build: () {
          buildCount += 1;
          return indexer.prepare(
            html: request.html,
            startAnchor: request.startAnchor,
          );
        },
      );
      final second = cache.resolve(
        request: request,
        build: () {
          buildCount += 1;
          return indexer.prepare(
            html: request.html,
            startAnchor: request.startAnchor,
          );
        },
      );

      final firstResult = await first;
      final secondResult = await second;
      expect(buildCount, 1);
      expect(firstResult.fromCache, isFalse);
      expect(firstResult.joinedInFlight, isFalse);
      expect(secondResult.fromCache, isFalse);
      expect(secondResult.joinedInFlight, isTrue);
      expect(secondResult.session, same(firstResult.session));

      final cached = await cache.resolve(
        request: request,
        build: () => throw StateError('cached sessions must not rebuild'),
      );
      expect(cached.fromCache, isTrue);
      expect(cached.joinedInFlight, isFalse);
      expect(cached.session, same(firstResult.session));
    },
  );

  test(
    'isolates exact HTML, anchors, revisions, and content identities',
    () async {
      final cache = NovelReaderComplexHtmlBoundaryCache(capacity: 8);
      const indexer = DefaultNovelReaderComplexHtmlBoundaryIndexer();
      var buildCount = 0;

      Future<void> resolve(
        NovelReaderComplexHtmlBoundaryCacheRequest request,
      ) async {
        await cache.resolve(
          request: request,
          build: () {
            buildCount += 1;
            return indexer.prepare(
              html: request.html,
              startAnchor: request.startAnchor,
            );
          },
        );
      }

      final baseline = _request('<p>正文 A。</p>');
      await resolve(baseline);
      await resolve(baseline);
      await resolve(_request('<p>正文 B。</p>'));
      await resolve(_request('<p>正文 A。</p>', contentHash: 'content-2'));
      await resolve(
        _request(
          '<p>正文 A。</p>',
          startAnchor: const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'node-1',
            textOffset: 10,
          ),
        ),
      );
      await resolve(_request('<p>正文 A。</p>', normalizerRevision: 2));
      await resolve(_request('<p>正文 A。</p>', boundaryIndexerRevision: 2));

      expect(buildCount, 6);
    },
  );

  test('evicts least recently used sessions at the configured bound', () async {
    final cache = NovelReaderComplexHtmlBoundaryCache(capacity: 2);
    const indexer = DefaultNovelReaderComplexHtmlBoundaryIndexer();
    var buildCount = 0;

    Future<void> resolve(String html) async {
      final request = _request(html);
      await cache.resolve(
        request: request,
        build: () {
          buildCount += 1;
          return indexer.prepare(
            html: request.html,
            startAnchor: request.startAnchor,
          );
        },
      );
    }

    await resolve('<p>A</p>');
    await resolve('<p>B</p>');
    await resolve('<p>A</p>');
    await resolve('<p>C</p>');
    await resolve('<p>B</p>');

    expect(cache.length, 2);
    expect(buildCount, 4);
  });
}

NovelReaderComplexHtmlBoundaryCacheRequest _request(
  String html, {
  String contentHash = 'content-1',
  NovelReaderTextAnchor startAnchor = const NovelReaderTextAnchor(
    episodeId: 'episode-1',
    nodeId: 'node-1',
  ),
  int normalizerRevision = 1,
  int boundaryIndexerRevision =
      NovelReaderComplexHtmlBoundaryIndexRevision.current,
}) {
  return NovelReaderComplexHtmlBoundaryCacheRequest(
    episodeId: 'episode-1',
    contentHash: contentHash,
    atomId: 'atom-1',
    html: html,
    startAnchor: startAnchor,
    normalizerRevision: normalizerRevision,
    boundaryIndexerRevision: boundaryIndexerRevision,
  );
}
