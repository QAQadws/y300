import 'dart:math' as math;

import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';

class NovelReaderProgressSnapshot {
  const NovelReaderProgressSnapshot({
    required this.novelId,
    required this.episodeId,
    required this.flowMode,
    required this.scrollOffset,
    required this.pageIndex,
    this.anchorNodeId,
    required this.progressPercent,
  });

  final String novelId;
  final String episodeId;
  final NovelReaderFlowMode flowMode;
  final double scrollOffset;
  final int pageIndex;
  final String? anchorNodeId;
  final double progressPercent;

  bool get isPaged => flowMode != NovelReaderFlowMode.vertical;

  NovelReaderProgressSnapshot copyWith({
    NovelReaderFlowMode? flowMode,
    double? scrollOffset,
    int? pageIndex,
    String? anchorNodeId,
    bool clearAnchorNodeId = false,
    double? progressPercent,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode ?? this.flowMode,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      anchorNodeId:
          clearAnchorNodeId ? null : (anchorNodeId ?? this.anchorNodeId),
      progressPercent: progressPercent ?? this.progressPercent,
    );
  }
}

class NovelReaderViewport {
  const NovelReaderViewport({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;
}

class NovelReaderPaginationMetrics {
  const NovelReaderPaginationMetrics({
    required this.bodyFontSize,
    required this.bodyLineHeight,
    required this.headingFontSize,
    required this.headingLineHeight,
    required this.paragraphSpacing,
    this.firstPageReservedHeight = 0,
  });

  final double bodyFontSize;
  final double bodyLineHeight;
  final double headingFontSize;
  final double headingLineHeight;
  final double paragraphSpacing;
  final double firstPageReservedHeight;
}

class NovelReaderPageSlice {
  const NovelReaderPageSlice({
    required this.index,
    required this.nodes,
    this.anchorNodeId,
  });

  final int index;
  final List<NovelReaderNode> nodes;
  final String? anchorNodeId;
}

class NovelReaderPageLayout {
  const NovelReaderPageLayout({
    required this.document,
    required this.pages,
  });

  final NovelReaderDocument document;
  final List<NovelReaderPageSlice> pages;

  int get pageCount => pages.isEmpty ? 1 : pages.length;

  int clampPageIndex(int pageIndex) {
    if (pageCount <= 1) {
      return 0;
    }
    return pageIndex.clamp(0, pageCount - 1).toInt();
  }

  NovelReaderPageSlice pageAt(int pageIndex) {
    if (pages.isEmpty) {
      return const NovelReaderPageSlice(index: 0, nodes: <NovelReaderNode>[]);
    }
    return pages[clampPageIndex(pageIndex)];
  }

  String? anchorForPage(int pageIndex) {
    return pageAt(pageIndex).anchorNodeId;
  }

  int pageIndexForAnchor(String? anchorNodeId) {
    final anchor = anchorNodeId?.trim();
    if (anchor == null || anchor.isEmpty) {
      return -1;
    }
    return pages.indexWhere((page) {
      if (page.anchorNodeId == anchor) {
        return true;
      }
      return page.nodes.any((node) => node.id == anchor);
    });
  }

  NovelReaderDocument documentForPage(int pageIndex) {
    final slice = pageAt(pageIndex);
    final plainText = slice.nodes
        .map(_textForNode)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
    return NovelReaderDocument(
      episodeId: document.episodeId,
      rawHtmlHash: document.rawHtmlHash,
      nodes: slice.nodes,
      plainText: plainText,
      wordCount: _countWords(plainText),
    );
  }
}

class NovelReaderPaginator {
  const NovelReaderPaginator();

  NovelReaderPageLayout paginate({
    required NovelReaderDocument document,
    required NovelReaderPaginationMetrics typography,
    required NovelReaderViewport viewportSize,
  }) {
    final safeHeight = math.max(120.0, viewportSize.height);
    final safeWidth = math.max(160.0, viewportSize.width);
    final pages = <NovelReaderPageSlice>[];
    var currentNodes = <NovelReaderNode>[];
    var currentHeight = 0.0;
    var currentPageHeightLimit = _pageHeightLimit(
      safeHeight,
      reservedHeight: typography.firstPageReservedHeight,
    );

    for (final node in document.nodes) {
      final nodeHeight = _estimateNodeHeight(
        node: node,
        metrics: typography,
        width: safeWidth,
        viewportHeight: safeHeight,
      );
      final spacing = currentNodes.isEmpty ? 0.0 : typography.paragraphSpacing;
      if (currentNodes.isNotEmpty &&
          currentHeight + spacing + nodeHeight > currentPageHeightLimit) {
        pages.add(_slice(pages.length, currentNodes));
        currentNodes = <NovelReaderNode>[node];
        currentHeight = nodeHeight;
        currentPageHeightLimit = safeHeight;
        continue;
      }
      currentNodes.add(node);
      currentHeight += spacing + nodeHeight;
    }

    if (currentNodes.isNotEmpty) {
      pages.add(_slice(pages.length, currentNodes));
    }
    if (pages.isEmpty) {
      pages.add(
        const NovelReaderPageSlice(index: 0, nodes: <NovelReaderNode>[]),
      );
    }
    return NovelReaderPageLayout(document: document, pages: pages);
  }

  double _pageHeightLimit(
    double safeHeight, {
    required double reservedHeight,
  }) {
    final effectiveReserved = reservedHeight.clamp(0.0, safeHeight - 80.0).toDouble();
    return math.max(80.0, safeHeight - effectiveReserved);
  }

  NovelReaderPageSlice _slice(int index, List<NovelReaderNode> nodes) {
    return NovelReaderPageSlice(
      index: index,
      nodes: List<NovelReaderNode>.unmodifiable(nodes),
      anchorNodeId: nodes.isEmpty ? null : nodes.first.id,
    );
  }

  double _estimateNodeHeight({
    required NovelReaderNode node,
    required NovelReaderPaginationMetrics metrics,
    required double width,
    required double viewportHeight,
  }) {
    switch (node.type) {
      case NovelReaderNodeType.heading:
        return _estimateTextHeight(
              _textForNode(node),
              width: width,
              fontSize: metrics.headingFontSize,
              lineHeight: metrics.headingLineHeight,
            ) +
            8;
      case NovelReaderNodeType.quote:
        return _estimateTextHeight(
              _textForNode(node),
              width: width - 16,
              fontSize: metrics.bodyFontSize,
              lineHeight: metrics.bodyLineHeight,
            ) +
            16;
      case NovelReaderNodeType.image:
        return math.min(
          math.max(140.0, width * 0.62),
          math.max(160.0, viewportHeight * 0.56),
        );
      case NovelReaderNodeType.link:
        return _estimateTextHeight(
              _textForNode(node),
              width: width,
              fontSize: metrics.bodyFontSize,
              lineHeight: metrics.bodyLineHeight,
            ) +
            12;
      case NovelReaderNodeType.divider:
        return 24;
      case NovelReaderNodeType.spacer:
        return math.max(8.0, metrics.paragraphSpacing);
      case NovelReaderNodeType.paragraph:
        return _estimateTextHeight(
          _textForNode(node),
          width: width,
          fontSize: metrics.bodyFontSize,
          lineHeight: metrics.bodyLineHeight,
        );
    }
  }

  double _estimateTextHeight(
    String text, {
    required double width,
    required double fontSize,
    required double lineHeight,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return fontSize * lineHeight;
    }
    final charsPerLine = math.max(6, (width / (fontSize * 0.92)).floor());
    final lines = normalized
        .split('\n')
        .map((line) => math.max(1, (line.runes.length / charsPerLine).ceil()))
        .fold<int>(0, (sum, value) => sum + value);
    return math.max(1, lines) * fontSize * lineHeight;
  }
}

class NovelReaderProgressPolicy {
  const NovelReaderProgressPolicy();

  NovelReaderProgressSnapshot initialSnapshot({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode,
      scrollOffset: 0,
      pageIndex: 0,
      progressPercent: 0,
    );
  }

  NovelReaderProgressSnapshot fromReadingProgress({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
    required NovelReadingProgress? progress,
  }) {
    if (progress == null || progress.episodeId != episodeId) {
      return initialSnapshot(
        novelId: novelId,
        episodeId: episodeId,
        flowMode: flowMode,
      );
    }
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode,
      scrollOffset: progress.scrollOffset,
      pageIndex: progress.pageIndex < 0 ? 0 : progress.pageIndex,
      anchorNodeId: _normalizeAnchor(progress.anchorNodeId),
      progressPercent: _clampPercent(progress.progressPercent),
    );
  }

  NovelReaderProgressSnapshot verticalSnapshot({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    double maxScrollExtent = 0,
    String? anchorNodeId,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: math.max(0.0, scrollOffset),
      pageIndex: 0,
      anchorNodeId: _normalizeAnchor(anchorNodeId),
      progressPercent: _percentFromOffset(scrollOffset, maxScrollExtent),
    );
  }

  NovelReaderProgressSnapshot pagedSnapshot({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
    required int pageIndex,
    required NovelReaderPageLayout layout,
  }) {
    final clamped = layout.clampPageIndex(pageIndex);
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode == NovelReaderFlowMode.vertical
          ? NovelReaderFlowMode.pagedLtr
          : flowMode,
      scrollOffset: 0,
      pageIndex: clamped,
      anchorNodeId: layout.anchorForPage(clamped),
      progressPercent:
          layout.pageCount <= 1 ? 0 : clamped / (layout.pageCount - 1),
    );
  }

  double restoreScrollOffset(
    NovelReaderProgressSnapshot snapshot, {
    required double maxScrollExtent,
  }) {
    return snapshot.scrollOffset.clamp(0.0, math.max(0.0, maxScrollExtent)).toDouble();
  }

  int restorePageIndex(
    NovelReaderProgressSnapshot snapshot, {
    required NovelReaderPageLayout layout,
  }) {
    final anchorIndex = layout.pageIndexForAnchor(snapshot.anchorNodeId);
    if (anchorIndex >= 0) {
      return layout.clampPageIndex(anchorIndex);
    }
    return layout.clampPageIndex(snapshot.pageIndex);
  }

  double _percentFromOffset(double offset, double maxScrollExtent) {
    if (maxScrollExtent <= 0) {
      return 0;
    }
    return _clampPercent(offset / maxScrollExtent);
  }

  double _clampPercent(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  String? _normalizeAnchor(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

String _textForNode(NovelReaderNode node) {
  final ownText = node.text?.trim();
  if (ownText != null && ownText.isNotEmpty) {
    return ownText;
  }
  final linkText = node.link?.text.trim();
  if (linkText != null && linkText.isNotEmpty) {
    return linkText;
  }
  return node.children
      .map(_textForNode)
      .where((text) => text.trim().isNotEmpty)
      .join('\n');
}

int _countWords(String text) {
  return text.runes
      .where((rune) => String.fromCharCode(rune).trim().isNotEmpty)
      .length;
}
