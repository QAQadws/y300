import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

enum NovelReaderPaginationPerformanceFallbackReason {
  firstPageBudgetExceeded,
  fullPlanBudgetExceeded,
}

@immutable
final class NovelReaderPaginationPerformanceBudget {
  const NovelReaderPaginationPerformanceBudget({
    required this.firstPage,
    required this.fullPlan,
  });

  final Duration firstPage;
  final Duration fullPlan;
}

/// Release guardrail for a single derived pagination session.
///
/// Debug mode is intentionally excluded by default because JIT, assertions
/// and test bindings are not representative of user-visible layout cost.
final class NovelReaderPaginationPerformancePolicy {
  const NovelReaderPaginationPerformancePolicy({
    this.plainTextBudget = const NovelReaderPaginationPerformanceBudget(
      firstPage: Duration(milliseconds: 500),
      fullPlan: Duration(seconds: 2),
    ),
    this.mixedContentBudget = const NovelReaderPaginationPerformanceBudget(
      firstPage: Duration(milliseconds: 800),
      fullPlan: Duration(seconds: 5),
    ),
    this.enforceBudgets = kProfileMode || kReleaseMode,
  });

  final NovelReaderPaginationPerformanceBudget plainTextBudget;
  final NovelReaderPaginationPerformanceBudget mixedContentBudget;
  final bool enforceBudgets;

  NovelReaderPaginationPerformanceFallbackReason? evaluate({
    required NovelReaderPaginationPlan plan,
    required Duration firstPageDuration,
    Duration? fullPlanDuration,
  }) {
    if (!enforceBudgets) {
      return null;
    }
    final budget = _isMixed(plan) ? mixedContentBudget : plainTextBudget;
    if (firstPageDuration > budget.firstPage) {
      return NovelReaderPaginationPerformanceFallbackReason
          .firstPageBudgetExceeded;
    }
    if (fullPlanDuration case final duration? when duration > budget.fullPlan) {
      return NovelReaderPaginationPerformanceFallbackReason
          .fullPlanBudgetExceeded;
    }
    return null;
  }

  bool _isMixed(NovelReaderPaginationPlan plan) {
    return plan.complexBlockCount > 0 ||
        plan.readableImageCount > 0 ||
        plan.safeTextFallbackCount > 0;
  }
}
