import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';
import 'forum_body_ruby_soft_space_contract.dart';
import 'forum_body_inline_plan_preparation.dart';
import 'forum_body_text_baseline_layout.dart';
import 'forum_body_inline_image_input.dart';

/// Source-bound image geometry, independent from glyph/annotation requests.
final class ForumBodyInlineImageAtomPlan extends ForumBodyRubyAtomPlan {
  ForumBodyInlineImageAtomPlan({required this.input, required this.maxWidth})
    : super._() {
    if (!maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384 ||
        input.dimensions.size.width > maxWidth ||
        input.dimensions.size.height > 16384) {
      throw ArgumentError('Inline image exceeds its parent geometry');
    }
  }
  final ForumBodyInlineImageInput input;
  @override
  final double maxWidth;
  @override
  List<ForumBodyTextRequest> get nativeRequests => const [];
  @override
  int get extraTextCodeUnits => input.retainedCodeUnits;
}

/// One actual parent placeholder's pure source requests and measured row target.
/// No native lease, owner, scheduler or page lifecycle belongs to this value.
sealed class ForumBodyRubyAtomPlan {
  const ForumBodyRubyAtomPlan._();
  factory ForumBodyRubyAtomPlan.textBaseline({
    required ForumBodyTextRequest request,
    required ForumBodyTextBaselineMetrics metrics,
    double maxWidth,
  }) = ForumBodyTextBaselineAtomPlan;
  factory ForumBodyRubyAtomPlan.column({
    required ForumBodyRubyColumnRequest request,
    ForumBodyRubyLevelMetrics? level,
    ForumBodyRubyGroupMetrics? metrics,
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
  Iterable<ForumBodyParagraphContent> get sourceContexts =>
      nativeRequests.map((r) => r.content);

  /// Exact retained glyph contexts for native band membership. They cannot
  /// replace the original current windows checked through [sourceContexts].
  Iterable<ForumBodyParagraphContent> get glyphContexts => sourceContexts;
  int get extraTextCodeUnits => 0;
  int get extraRuns => 0;
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint sync* {
    for (final request in nativeRequests) {
      yield (request: request, width: maxWidth, minimumLineCount: 1);
    }
  }

  Iterable<ForumBodyNativeBudgetSlot> get nativeBudgetFootprint =>
      nativeFootprint;
}

/// One measured, unbroken text group. Its own native parent and original child
/// windows share the existing page budget without acquiring ruby/RT roles.
final class ForumBodyIntrinsicInlineAtomPlan extends ForumBodyRubyAtomPlan {
  ForumBodyIntrinsicInlineAtomPlan({
    required this.metrics,
    this.maxWidth = 16384,
  }) : super._() {
    if (!maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384 ||
        metrics.size.width > maxWidth ||
        metrics.size.height <= 0 ||
        metrics.size.height > 16384 ||
        metrics.input.rubyAtoms.any(
          (atom) => atom is! ForumBodyTextBaselineAtomPlan,
        )) {
      throw ArgumentError('Invalid intrinsic text atom');
    }
  }
  final ForumBodyIntrinsicInlineMetrics metrics;
  @override
  final double maxWidth;
  @override
  late final List<ForumBodyTextRequest> nativeRequests = List.unmodifiable([
    for (final atom in metrics.input.rubyAtoms) ...atom.nativeRequests,
  ]);
  @override
  Iterable<ForumBodyParagraphContent> get sourceContexts =>
      metrics.input.content.contexts.map((c) => c.content);
  @override
  int get extraTextCodeUnits => metrics.input.retainedTextCodeUnits;
  @override
  int get extraRuns => metrics.input.retainedRuns;
  @override
  int get nativeHandleCount => metrics.nativeHandleCount;
  @override
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint =>
      metrics.input.nativeFootprintFor(metrics.fragment);
  @override
  Iterable<ForumBodyNativeBudgetSlot> get nativeBudgetFootprint =>
      metrics.input.nativeBudgetFootprintFor(metrics.fragment);
}

/// A shifted text box keeps exactly one original source context.
final class ForumBodyTextBaselineAtomPlan extends ForumBodyRubyAtomPlan {
  ForumBodyTextBaselineAtomPlan({
    required this.request,
    required this.metrics,
    this.maxWidth = 16384,
  }) : super._() {
    if (!maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384 ||
        metrics.size.width > maxWidth ||
        metrics.size.height <= 0 ||
        metrics.size.height > 16384 ||
        request.content.layoutMode !=
            ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
      throw ArgumentError('Invalid baseline text atom');
    }
  }
  final ForumBodyTextRequest request;
  final ForumBodyTextBaselineMetrics metrics;
  @override
  final double maxWidth;
  @override
  List<ForumBodyTextRequest> get nativeRequests => [request];
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
  ForumBodyRubyColumnPlan({required this.request, this.level, this.metrics})
    : super._() {
    if (level != null &&
        (level!.annotations.length != request.annotations.length ||
            request.annotations.indexed.any(
              (item) => item.$2.side != level!.annotations[item.$1].side,
            ))) {
      throw ArgumentError('Ruby row target does not match column ranks');
    }
    final measured = metrics;
    if (measured != null &&
        (request.annotations.length != measured.annotations.length ||
            request.annotations.indexed.any(
              (item) => item.$2.side != measured.annotations[item.$1].side,
            ) ||
            (level != null && !level!.contains(measured)))) {
      throw ArgumentError('Ruby column metrics differ from its row target');
    }
  }
  final ForumBodyRubyColumnRequest request;
  final ForumBodyRubyLevelMetrics? level;

  /// Actual final aligned geometry. Legacy explicit plans may omit it; numeric
  /// font/annotation consumers must require it instead of guessing from a slot.
  final ForumBodyRubyGroupMetrics? metrics;
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
