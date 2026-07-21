import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_layout_policy.dart';

abstract interface class NovelReaderPaginationLayoutPolicyResolver {
  NovelReaderPaginationLayoutPolicy resolve(NovelReaderPaginationRoute route);
}

final class DefaultNovelReaderPaginationLayoutPolicyResolver
    implements NovelReaderPaginationLayoutPolicyResolver {
  const DefaultNovelReaderPaginationLayoutPolicyResolver();

  static const safeText = NovelReaderPaginationLayoutPolicy(
    measure: NovelReaderPaginationMeasurePolicy.textPainter,
    split: NovelReaderPaginationSplitPolicy.lineRanges,
    placement: NovelReaderPaginationPlacementPolicy.flow,
    overflow: NovelReaderPaginationOverflowPolicy.minimumTextFragment,
    keepPageOpenAfterAppend: true,
  );

  static const flowableComplexText = NovelReaderPaginationLayoutPolicy(
    measure: NovelReaderPaginationMeasurePolicy.htmlRendererRange,
    split: NovelReaderPaginationSplitPolicy.domBoundaries,
    placement: NovelReaderPaginationPlacementPolicy.flow,
    overflow: NovelReaderPaginationOverflowPolicy.fallbackToVertical,
    keepPageOpenAfterAppend: true,
  );

  static const dedicatedContent = NovelReaderPaginationLayoutPolicy(
    measure: NovelReaderPaginationMeasurePolicy.htmlRendererWholeAtom,
    split: NovelReaderPaginationSplitPolicy.none,
    placement: NovelReaderPaginationPlacementPolicy.dedicatedPage,
    overflow: NovelReaderPaginationOverflowPolicy.innerScroll,
    keepPageOpenAfterAppend: false,
  );

  static const atomicWidget = NovelReaderPaginationLayoutPolicy(
    measure: NovelReaderPaginationMeasurePolicy.htmlRendererWholeAtom,
    split: NovelReaderPaginationSplitPolicy.none,
    placement: NovelReaderPaginationPlacementPolicy.dedicatedPage,
    overflow: NovelReaderPaginationOverflowPolicy.innerScroll,
    keepPageOpenAfterAppend: false,
  );

  @override
  NovelReaderPaginationLayoutPolicy resolve(NovelReaderPaginationRoute route) {
    return switch (route) {
      NovelReaderPaginationRoute.safeText => safeText,
      NovelReaderPaginationRoute.flowableComplexText ||
      NovelReaderPaginationRoute.rubyInline => flowableComplexText,
      NovelReaderPaginationRoute.isolatedImage ||
      NovelReaderPaginationRoute.tableBlock ||
      NovelReaderPaginationRoute.collapseBlock => dedicatedContent,
      NovelReaderPaginationRoute.atomicWidget ||
      NovelReaderPaginationRoute.complexHtml => atomicWidget,
    };
  }
}
