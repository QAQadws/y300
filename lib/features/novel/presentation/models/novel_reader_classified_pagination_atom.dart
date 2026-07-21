import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_layout_policy.dart';

enum NovelReaderPaginationRoute {
  safeText,
  flowableComplexText,
  rubyInline,
  isolatedImage,
  collapseBlock,
  tableBlock,
  atomicWidget,
  // Transitional route for persisted diagnostics and explicit legacy tests.
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
    required this.reason,
    required this.layoutPolicy,
  });

  final NovelReaderPaginationAtom atom;
  final NovelReaderPaginationRoute route;
  final NovelReaderPaginationRouteReason reason;
  final NovelReaderPaginationLayoutPolicy layoutPolicy;

  bool get isBreakable => layoutPolicy.isBreakable;
}
