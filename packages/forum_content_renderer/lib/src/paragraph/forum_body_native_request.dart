import 'package:flutter/painting.dart';

import 'forum_body_paragraph_cache.dart';

typedef ForumBodyNativeRequestSlot = ({
  ForumBodyNativeRequest request,
  double width,
  int minimumLineCount,
});

/// One real native layout request. A composite may include ordinary text,
/// shared-band children and inline parents in the SAME cache footprint.
/// This port intentionally has no source-context getter: a placeholder parent
/// is a native handle, not another independently shaped source-text leaf.
/// Requests own no lease, scaler, owner callback or scheduling policy.
abstract class ForumBodyNativeRequest {
  const ForumBodyNativeRequest();

  ForumBodyNativeParagraphLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  });

  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  });
}
