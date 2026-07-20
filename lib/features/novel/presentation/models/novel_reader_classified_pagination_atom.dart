import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';

enum NovelReaderPaginationRoute {
  safeText,
  rubyInline,
  isolatedImage,
  collapseBlock,
  tableBlock,
  complexHtml,
}

enum NovelReaderPaginationRouteReason {
  safeTextSubset,
  containsRuby,
  isolatedReadableImage,
  containsCollapse,
  containsTable,
  containsImage,
  containsWidgetSpan,
  unsupportedTag,
  unsupportedAttribute,
  unsupportedStyle,
  unsupportedFont,
  atomicWidget,
}

final class NovelReaderClassifiedPaginationAtom {
  const NovelReaderClassifiedPaginationAtom({
    required this.atom,
    required this.route,
    required this.isBreakable,
    required this.reason,
  });

  final NovelReaderPaginationAtom atom;
  final NovelReaderPaginationRoute route;
  final bool isBreakable;
  final NovelReaderPaginationRouteReason reason;
}
