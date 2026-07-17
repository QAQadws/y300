import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_layout_request.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_layout_service.dart';

void main() {
  test(
    'same key concurrent resolve paginates once and reuses future',
    () async {
      final paginator = _RecordingPaginator();
      final service = CachedNovelReaderLayoutService(paginator: paginator);
      final request = _request();

      final futures = <Future<NovelReaderPageLayout>>[
        service.resolve(request),
        service.resolve(request),
      ];
      final results = await Future.wait(futures);

      expect(identical(results[0], results[1]), isTrue);
      expect(paginator.callCount, 1);
    },
  );

  test('second same key resolve hits cache', () async {
    final paginator = _RecordingPaginator();
    final service = CachedNovelReaderLayoutService(paginator: paginator);
    final request = _request();

    final first = await service.resolve(request);
    final second = await service.resolve(request);

    expect(identical(first, second), isTrue);
    expect(paginator.callCount, 1);
  });

  test('evictEpisode only clears keys for matching episode', () async {
    final paginator = _RecordingPaginator();
    final service = CachedNovelReaderLayoutService(paginator: paginator);
    final first = _request(episodeId: 'episode-1');
    final second = _request(episodeId: 'episode-2', rawHtmlHash: 'hash-2');

    await service.resolve(first);
    await service.resolve(second);
    expect(paginator.callCount, 2);

    service.evictEpisode('episode-1');
    await service.resolve(first);
    await service.resolve(second);

    expect(paginator.callCount, 3);
  });
}

class _RecordingPaginator extends NovelReaderPaginator {
  int callCount = 0;
  final List<NovelReaderPaginationMetrics> metricsByCall =
      <NovelReaderPaginationMetrics>[];

  @override
  NovelReaderPageLayout paginate({
    required NovelReaderDocument document,
    required NovelReaderPaginationMetrics typography,
    required NovelReaderViewport viewportSize,
  }) {
    callCount += 1;
    metricsByCall.add(typography);
    return NovelReaderPageLayout(
      document: document,
      pages: [
        NovelReaderPageSlice(
          index: 0,
          blocks: document.blocks,
          anchorNodeId: document.blocks.isEmpty
              ? null
              : document.blocks.first.anchorId,
        ),
      ],
    );
  }
}

NovelReaderLayoutRequest _request({
  String episodeId = 'episode-1',
  String rawHtmlHash = 'hash-1',
}) {
  return NovelReaderLayoutRequest(
    episodeId: episodeId,
    rawHtmlHash: rawHtmlHash,
    document: NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: rawHtmlHash,
      body: const RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            anchorId: 'node-1',
            runs: <RichRun>[RichRun(text: '正文')],
          ),
        ],
      ),
      plainText: '正文',
      wordCount: 2,
    ),
    viewport: const NovelReaderViewport(width: 360, height: 640),
    metrics: NovelReaderPaginationMetrics(
      bodyFontSize: 18,
      bodyLineHeight: 1.8,
      headingFontSize: 22,
      headingLineHeight: 1.3,
      paragraphSpacing: 10,
      firstPageReservedHeight: 0,
    ),
    pagePadding: 16,
    contentMaxWidth: 720,
    fontWeight: 400,
    fontFamily: 'system',
    textAlign: 'start',
    firstLineIndent: 0,
  );
}
