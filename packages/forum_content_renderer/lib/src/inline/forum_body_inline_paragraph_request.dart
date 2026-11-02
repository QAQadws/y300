import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_inline_span_content.dart';

/// Pure native parent input, including its already resolved placeholder geometry
/// and layout mode. Cache admission and cached acquisition use these SAME
/// inputs; source ownership still belongs to the complete inline plan/view.
final class ForumBodyInlineParagraphRequest extends ForumBodyNativeRequest {
  ForumBodyInlineParagraphRequest({
    required this.content,
    required List<PlaceholderDimensions> dimensions,
    this.layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : dimensions = List.unmodifiable(dimensions);

  final ForumBodyInlineSpanContent content;
  final List<PlaceholderDimensions> dimensions;
  final ForumBodyParagraphLayoutMode layoutMode;

  @override
  ForumBodyInlineParagraphLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  }) => cachedOnly
      ? cache.tryAcquireInlineCached(
          content: content,
          width: width,
          dimensions: dimensions,
          textScaler: textScaler,
          layoutMode: layoutMode,
        )
      : cache.acquireInline(
          content: content,
          width: width,
          dimensions: dimensions,
          textScaler: textScaler,
          layoutMode: layoutMode,
        );

  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) => probe.includeInline(
    content: content,
    width: width,
    dimensions: dimensions,
    textScaler: textScaler,
    layoutMode: layoutMode,
    minimumLineCount: minimumLineCount,
  );
}
