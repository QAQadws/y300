import 'dart:math' as math;

enum ForumBodyEmphasisAllocationFailure { source, geometry, limit }

final class ForumBodyEmphasisAllocationException implements Exception {
  const ForumBodyEmphasisAllocationException(this.failure);
  final ForumBodyEmphasisAllocationFailure failure;
  @override
  String toString() => 'ForumBodyEmphasisAllocationException(${failure.name})';
}

/// Shared physical frame rule for ordinary and mixed emphasis rows. Only final
/// allocated advances accumulate; authored/native coordinates stay measured.
({double height, double baseline, double translationY})
forumBodyAllocateEmphasisRowFrame({
  required double ascent,
  required double authoredAdvance,
  required double originalBaseline,
  required double extentTop,
  required double extentBottom,
  required double flowTop,
  required double maxHeight,
}) {
  final top = extentTop - originalBaseline,
      bottom = extentBottom - originalBaseline;
  final relativeBaseline = math.max(ascent, -top);
  final height = math.max(
    authoredAdvance + relativeBaseline - ascent,
    relativeBaseline + bottom,
  );
  final baseline = flowTop + relativeBaseline,
      delta = baseline - originalBaseline;
  if (![
        ascent,
        relativeBaseline,
        authoredAdvance,
        height,
        baseline,
        delta,
      ].every((v) => v.isFinite) ||
      authoredAdvance < 0 ||
      height < 0) {
    throw const ForumBodyEmphasisAllocationException(
      ForumBodyEmphasisAllocationFailure.geometry,
    );
  }
  if (flowTop + height > maxHeight) {
    throw const ForumBodyEmphasisAllocationException(
      ForumBodyEmphasisAllocationFailure.limit,
    );
  }
  return (height: height, baseline: baseline, translationY: delta);
}
