import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import 'forum_body_emphasis_mark.dart';

/// Source-free font work in the owner's common native request/budget manifest.
final class ForumBodyEmphasisMarkRequest extends ForumBodyNativeRequest {
  const ForumBodyEmphasisMarkRequest(this.input);
  final ForumBodyEmphasisMarkInput input;
  @override
  ForumBodyEmphasisMarkLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  }) => cachedOnly
      ? cache.tryAcquireEmphasisMarkCached(input: input, textScaler: textScaler)
      : cache.acquireEmphasisMark(input: input, textScaler: textScaler);
  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) {
    RangeError.checkValueInInterval(minimumLineCount, 0, 1, 'minimumLineCount');
    probe.includeEmphasisMark(input: input, textScaler: textScaler);
  }
}
