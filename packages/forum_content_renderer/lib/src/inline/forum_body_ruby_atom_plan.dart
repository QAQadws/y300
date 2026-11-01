import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';
import 'forum_body_ruby_soft_space_contract.dart';

/// One actual parent placeholder's pure source requests and measured row target.
/// No native lease, owner, scheduler or page lifecycle belongs to this value.
sealed class ForumBodyRubyAtomPlan {
  const ForumBodyRubyAtomPlan._();
  factory ForumBodyRubyAtomPlan.column({
    required ForumBodyRubyColumnRequest request,
    ForumBodyRubyLevelMetrics? level,
  }) = ForumBodyRubyColumnPlan;
  factory ForumBodyRubyAtomPlan.segment({
    required ForumBodyRubySegmentRequest request,
    required ForumBodyRubySegmentMetrics metrics,
  }) = ForumBodyRubySegmentPlan;
  factory ForumBodyRubyAtomPlan.softSpace({
    required ForumBodyRubySoftSpaceRequest request,
    required ForumBodyRubySoftSpaceMetrics metrics,
  }) = ForumBodyRubySoftSpacePlan;
  List<ForumBodyTextRequest> get nativeRequests;
  double get maxWidth;
  int get nativeHandleCount => nativeRequests.length;
}

final class ForumBodyRubySoftSpacePlan extends ForumBodyRubyAtomPlan {
  ForumBodyRubySoftSpacePlan({required this.request, required this.metrics})
    : super._() {
    validateForumBodyRubySoftSpaceTarget(request, metrics);
    for (var rank = 0; rank < request.sides.length; rank++) {
      validateForumBodyRubySoftSpaceRank(request, metrics, rank);
    }
    for (var i = 0; i < request.members.length; i++) {
      validateForumBodyRubySoftSpaceMember(request, metrics, i);
    }
  }
  final ForumBodyRubySoftSpaceRequest request;
  final ForumBodyRubySoftSpaceMetrics metrics;
  @override
  List<ForumBodyTextRequest> get nativeRequests => request.nativeRequests;
  @override
  double get maxWidth => request.maxWidth;
}

final class ForumBodyRubyColumnPlan extends ForumBodyRubyAtomPlan {
  ForumBodyRubyColumnPlan({required this.request, this.level}) : super._() {
    if (level != null &&
        (level!.annotations.length != request.annotations.length ||
            request.annotations.indexed.any(
              (item) => item.$2.side != level!.annotations[item.$1].side,
            ))) {
      throw ArgumentError('Ruby row target does not match column ranks');
    }
  }
  final ForumBodyRubyColumnRequest request;
  final ForumBodyRubyLevelMetrics? level;
  @override
  List<ForumBodyTextRequest> get nativeRequests => request.nativeRequests;
  @override
  double get maxWidth => request.maxWidth;
}

final class ForumBodyRubySegmentPlan extends ForumBodyRubyAtomPlan {
  ForumBodyRubySegmentPlan({required this.request, required this.metrics})
    : super._() {
    if (request.direction != metrics.direction ||
        metrics.size.width > request.maxWidth ||
        request.bases.length != metrics.columns.length ||
        request.spans.length != metrics.spans.length ||
        request.gaps.length != metrics.gaps.length ||
        request.annotationGaps.length != metrics.annotationGaps.length ||
        request.sides.length != metrics.level.annotations.length) {
      throw ArgumentError(
        'Ruby segment target does not match original request',
      );
    }
    for (final (rank, side) in request.sides.indexed) {
      if (side != metrics.level.annotations[rank].side) {
        throw ArgumentError(
          'Ruby segment target does not match original ranks',
        );
      }
    }
    for (final (index, gap) in request.gaps.indexed) {
      if (gap.beforeColumn != metrics.gaps[index].input.beforeColumn) {
        throw ArgumentError('Ruby segment target does not match original gap');
      }
    }
    for (final (index, gap) in request.annotationGaps.indexed) {
      final target = metrics.annotationGaps[index];
      final next = request.spans[gap.beforeSpanIndex];
      if (gap.beforeSpanIndex != target.beforeSpanIndex ||
          next.startColumn != target.input.beforeColumn ||
          next.annotationIndex != target.input.annotationIndex ||
          request.sides[next.annotationIndex] != target.input.annotation.side ||
          gap.gap != target.input.annotation.gap) {
        throw ArgumentError(
          'Ruby segment target does not match original annotation gap',
        );
      }
    }
    for (final (index, span) in request.spans.indexed) {
      final target = metrics.spans[index].input;
      if (span.startColumn != target.startColumn ||
          span.endColumn != target.endColumn ||
          span.annotationIndex != target.annotationIndex ||
          span.gap != target.annotation.gap ||
          request.sides[span.annotationIndex] != target.annotation.side ||
          span.request.content.projection.text.isNotEmpty !=
              target.annotation.hasAnnotation) {
        throw ArgumentError('Ruby segment target does not match original span');
      }
    }
  }
  final ForumBodyRubySegmentRequest request;
  final ForumBodyRubySegmentMetrics metrics;
  @override
  List<ForumBodyTextRequest> get nativeRequests => request.nativeRequests;
  @override
  double get maxWidth => request.maxWidth;
}
