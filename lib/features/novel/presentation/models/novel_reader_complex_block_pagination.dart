import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';

final class NovelReaderRubyCluster {
  const NovelReaderRubyCluster({
    required this.clusterId,
    required this.clusterStart,
    required this.clusterEnd,
    required this.baseStart,
    required this.baseEnd,
    required this.annotationStart,
    required this.annotationEnd,
  });

  final String clusterId;
  final int clusterStart;
  final int clusterEnd;
  final int baseStart;
  final int baseEnd;
  final int annotationStart;
  final int annotationEnd;

  bool get isPaired => baseEnd > baseStart && annotationEnd > annotationStart;
}

final class NovelReaderRubyPaginationDescriptor {
  NovelReaderRubyPaginationDescriptor({
    required List<NovelReaderRubyCluster> clusters,
    required this.annotationElementCount,
    required this.fallbackElementCount,
  }) : clusters = List<NovelReaderRubyCluster>.unmodifiable(clusters);

  final List<NovelReaderRubyCluster> clusters;
  final int annotationElementCount;
  final int fallbackElementCount;

  bool get allClustersPaired => clusters.every((cluster) => cluster.isPaired);
}

final class NovelReaderCollapseBlockState {
  const NovelReaderCollapseBlockState({
    required this.blockId,
    required this.depth,
    required this.initiallyExpanded,
  });

  final String blockId;
  final int depth;
  final bool initiallyExpanded;
}

final class NovelReaderCollapsePaginationDescriptor {
  NovelReaderCollapsePaginationDescriptor({
    required List<NovelReaderCollapseBlockState> blocks,
  }) : blocks = List<NovelReaderCollapseBlockState>.unmodifiable(blocks);

  final List<NovelReaderCollapseBlockState> blocks;

  int get expandedCount =>
      blocks.where((block) => block.initiallyExpanded).length;
  int get nestedCount => blocks.where((block) => block.depth > 0).length;
}

final class NovelReaderTablePaginationDescriptor {
  const NovelReaderTablePaginationDescriptor({
    required this.tableCount,
    required this.rowCount,
    required this.cellCount,
  });

  final int tableCount;
  final int rowCount;
  final int cellCount;
}

final class NovelReaderComplexBlockMetrics {
  const NovelReaderComplexBlockMetrics({
    required this.height,
    required this.route,
    required this.isOversized,
    required this.requiresInnerScroll,
    required this.measurementCacheHit,
    required this.frameWaitCount,
    this.ruby,
    this.collapse,
    this.table,
  });

  final double height;
  final NovelReaderPaginationRoute route;
  final bool isOversized;
  final bool requiresInnerScroll;
  final bool measurementCacheHit;
  final int frameWaitCount;
  final NovelReaderRubyPaginationDescriptor? ruby;
  final NovelReaderCollapsePaginationDescriptor? collapse;
  final NovelReaderTablePaginationDescriptor? table;
}

final class NovelReaderComplexBlockPage {
  const NovelReaderComplexBlockPage({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.metrics,
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final NovelReaderComplexBlockMetrics metrics;
}
