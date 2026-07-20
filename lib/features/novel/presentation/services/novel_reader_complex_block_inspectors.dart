import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/models/novel_reader_complex_block_pagination.dart';

final class NovelReaderRubyPaginationAdapter {
  const NovelReaderRubyPaginationAdapter();

  NovelReaderRubyPaginationDescriptor inspect(String html) {
    final fragment = html_parser.parseFragment(html);
    final clusters = <NovelReaderRubyCluster>[];
    final cursor = _RubyTextCursor();
    _walk(fragment, cursor, clusters);
    return NovelReaderRubyPaginationDescriptor(
      clusters: clusters,
      annotationElementCount: fragment.querySelectorAll('rt').length,
      fallbackElementCount: fragment.querySelectorAll('rp').length,
    );
  }

  void _walk(
    html_dom.Node node,
    _RubyTextCursor cursor,
    List<NovelReaderRubyCluster> clusters, {
    _RubyClusterBuilder? activeCluster,
    bool annotation = false,
  }) {
    if (node is html_dom.Text) {
      final start = cursor.offset;
      cursor.offset += node.data.runes.length;
      activeCluster?.record(
        start: start,
        end: cursor.offset,
        annotation: annotation,
      );
      return;
    }
    if (node is! html_dom.Element && node is! html_dom.DocumentFragment) {
      return;
    }
    if (node is html_dom.Element && node.localName?.toLowerCase() == 'ruby') {
      final builder = _RubyClusterBuilder(
        clusterId: _clusterId(node.outerHtml, clusters.length),
        clusterStart: cursor.offset,
      );
      for (final child in node.nodes) {
        _walk(
          child,
          cursor,
          clusters,
          activeCluster: builder,
          annotation:
              child is html_dom.Element &&
              const <String>{
                'rt',
                'rp',
              }.contains(child.localName?.toLowerCase()),
        );
      }
      clusters.add(builder.build(cursor.offset));
      return;
    }
    for (final child in node.nodes) {
      final childIsAnnotation =
          annotation ||
          (child is html_dom.Element &&
              const <String>{
                'rt',
                'rp',
              }.contains(child.localName?.toLowerCase()));
      _walk(
        child,
        cursor,
        clusters,
        activeCluster: activeCluster,
        annotation: childIsAnnotation,
      );
    }
  }

  String _clusterId(String html, int occurrence) {
    var hash = 0x811c9dc5;
    for (final unit in html.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'ruby-${hash.toRadixString(16).padLeft(8, '0')}-$occurrence';
  }
}

final class NovelReaderCollapsePaginationAdapter {
  const NovelReaderCollapsePaginationAdapter();

  NovelReaderCollapsePaginationDescriptor inspect(String html) {
    final fragment = html_parser.parseFragment(html);
    final elements = fragment.querySelectorAll('.showcollapse_box');
    final occurrences = <String, int>{};
    final blocks = <NovelReaderCollapseBlockState>[];
    for (final element in elements) {
      final identity = element.id.isNotEmpty
          ? 'id-${element.id}'
          : 'html-${_stableHash(element.outerHtml)}';
      final occurrence = occurrences.update(
        identity,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      blocks.add(
        NovelReaderCollapseBlockState(
          blockId: '$identity-$occurrence',
          depth: _collapseDepth(element),
          initiallyExpanded: element.classes.contains('showcollapse_active'),
        ),
      );
    }
    return NovelReaderCollapsePaginationDescriptor(blocks: blocks);
  }

  int _collapseDepth(html_dom.Element element) {
    var depth = 0;
    html_dom.Node? ancestor = element.parentNode;
    while (ancestor != null) {
      if (ancestor is html_dom.Element &&
          ancestor.classes.contains('showcollapse_box')) {
        depth += 1;
      }
      ancestor = ancestor.parentNode;
    }
    return depth;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

final class NovelReaderTablePaginationAdapter {
  const NovelReaderTablePaginationAdapter();

  NovelReaderTablePaginationDescriptor inspect(String html) {
    final fragment = html_parser.parseFragment(html);
    return NovelReaderTablePaginationDescriptor(
      tableCount: fragment.querySelectorAll('table').length,
      rowCount: fragment.querySelectorAll('tr').length,
      cellCount: fragment.querySelectorAll('td,th').length,
    );
  }
}

final class _RubyTextCursor {
  int offset = 0;
}

final class _RubyClusterBuilder {
  _RubyClusterBuilder({required this.clusterId, required this.clusterStart});

  final String clusterId;
  final int clusterStart;
  int? baseStart;
  int? baseEnd;
  int? annotationStart;
  int? annotationEnd;

  void record({
    required int start,
    required int end,
    required bool annotation,
  }) {
    if (annotation) {
      annotationStart ??= start;
      annotationEnd = end;
    } else {
      baseStart ??= start;
      baseEnd = end;
    }
  }

  NovelReaderRubyCluster build(int clusterEnd) {
    return NovelReaderRubyCluster(
      clusterId: clusterId,
      clusterStart: clusterStart,
      clusterEnd: clusterEnd,
      baseStart: baseStart ?? clusterStart,
      baseEnd: baseEnd ?? clusterStart,
      annotationStart: annotationStart ?? clusterEnd,
      annotationEnd: annotationEnd ?? clusterEnd,
    );
  }
}
