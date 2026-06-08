import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

void main() {
  const paginator = NovelReaderPaginator();
  const policy = NovelReaderProgressPolicy();
  const metrics = NovelReaderPaginationMetrics(
    bodyFontSize: 18,
    bodyLineHeight: 1.8,
    headingFontSize: 24,
    headingLineHeight: 1.3,
    paragraphSpacing: 10,
  );

  test('NovelReaderPaginator creates at least one page for empty document', () {
    final layout = paginator.paginate(
      document: _document(const <NovelReaderNode>[]),
      typography: metrics,
      viewportSize: const NovelReaderViewport(width: 360, height: 640),
    );

    expect(layout.pageCount, 1);
    expect(layout.pageAt(0).nodes, isEmpty);
  });

  test('NovelReaderPaginator paginates by viewport and node estimates', () {
    final layout = paginator.paginate(
      document: _document(
        List<NovelReaderNode>.generate(
          12,
          (index) => NovelReaderNode(
            id: 'node-$index',
            type: NovelReaderNodeType.paragraph,
            text: '第$index段 ${List<String>.filled(80, '正文').join()}',
          ),
        ),
      ),
      typography: metrics,
      viewportSize: const NovelReaderViewport(width: 320, height: 260),
    );

    expect(layout.pageCount, greaterThan(1));
    expect(layout.pageAt(0).anchorNodeId, 'node-0');
    expect(layout.pageAt(1).nodes.first.id, isNot('node-0'));
  });

  test('NovelReaderProgressPolicy clamps old page after layout changes', () {
    final layout = paginator.paginate(
      document: _document(
        const <NovelReaderNode>[
          NovelReaderNode(
            id: 'node-0',
            type: NovelReaderNodeType.paragraph,
            text: '短正文',
          ),
        ],
      ),
      typography: metrics,
      viewportSize: const NovelReaderViewport(width: 360, height: 640),
    );
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'ep1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 99,
      progressPercent: 1,
    );

    expect(policy.restorePageIndex(snapshot, layout: layout), 0);
  });

  test('NovelReaderProgressPolicy restores page by anchor before page index', () {
    final layout = NovelReaderPageLayout(
      document: _document(const <NovelReaderNode>[]),
      pages: const <NovelReaderPageSlice>[
        NovelReaderPageSlice(index: 0, nodes: <NovelReaderNode>[], anchorNodeId: 'a'),
        NovelReaderPageSlice(index: 1, nodes: <NovelReaderNode>[], anchorNodeId: 'b'),
      ],
    );
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:1',
      episodeId: 'ep1',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorNodeId: 'b',
      progressPercent: 0,
    );

    expect(policy.restorePageIndex(snapshot, layout: layout), 1);
  });

  test('NovelReaderProgressPolicy builds vertical and paged snapshots', () {
    final vertical = policy.verticalSnapshot(
      novelId: 'novel:1',
      episodeId: 'ep1',
      scrollOffset: 50,
      maxScrollExtent: 200,
    );
    expect(vertical.flowMode, NovelReaderFlowMode.vertical);
    expect(vertical.progressPercent, 0.25);

    final layout = NovelReaderPageLayout(
      document: _document(const <NovelReaderNode>[]),
      pages: const <NovelReaderPageSlice>[
        NovelReaderPageSlice(index: 0, nodes: <NovelReaderNode>[], anchorNodeId: 'a'),
        NovelReaderPageSlice(index: 1, nodes: <NovelReaderNode>[], anchorNodeId: 'b'),
        NovelReaderPageSlice(index: 2, nodes: <NovelReaderNode>[], anchorNodeId: 'c'),
      ],
    );
    final paged = policy.pagedSnapshot(
      novelId: 'novel:1',
      episodeId: 'ep1',
      flowMode: NovelReaderFlowMode.pagedRtl,
      pageIndex: 2,
      layout: layout,
    );
    expect(paged.flowMode, NovelReaderFlowMode.pagedRtl);
    expect(paged.pageIndex, 2);
    expect(paged.anchorNodeId, 'c');
    expect(paged.progressPercent, 1);
  });
}

NovelReaderDocument _document(List<NovelReaderNode> nodes) {
  return NovelReaderDocument(
    episodeId: 'ep1',
    rawHtmlHash: 'hash',
    nodes: nodes,
    plainText: nodes.map((node) => node.text ?? '').join('\n'),
    wordCount: 0,
  );
}
