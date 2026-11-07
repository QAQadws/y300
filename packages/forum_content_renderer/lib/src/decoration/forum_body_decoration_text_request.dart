import 'package:flutter/painting.dart';

import 'forum_body_decoration_text.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';

/// Source-free labels use the existing owner cache, probe and pin lifecycle.
/// Width is an intrinsic request input; placement/fit belongs to the consumer.
final class ForumBodyDecorationTextRequest extends ForumBodyNativeRequest {
  const ForumBodyDecorationTextRequest(this.input);
  final ForumBodyDecorationTextInput input;

  @override
  ForumBodyDecorationTextLease? acquire(
    ForumBodyParagraphCache cache, {
    required double width,
    required TextScaler textScaler,
    required bool cachedOnly,
  }) => cachedOnly
      ? cache.tryAcquireDecorationTextCached(
          input: input,
          textScaler: textScaler,
        )
      : cache.acquireDecorationText(input: input, textScaler: textScaler);

  @override
  void includeBudget(
    ForumBodyParagraphBudgetProbe probe, {
    required double width,
    required TextScaler textScaler,
    int minimumLineCount = 1,
  }) {
    RangeError.checkValueInInterval(minimumLineCount, 0, 1, 'minimumLineCount');
    probe.includeDecorationText(input: input, textScaler: textScaler);
  }
}
