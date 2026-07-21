import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

void main() {
  const policy = NovelReaderPaginationPerformancePolicy(enforceBudgets: true);

  test('plain text uses the strict first-page and full-plan budgets', () {
    final plan = _plan();

    expect(
      policy.evaluate(
        plan: plan,
        firstPageDuration: const Duration(milliseconds: 501),
      ),
      NovelReaderPaginationPerformanceFallbackReason.firstPageBudgetExceeded,
    );
    expect(
      policy.evaluate(
        plan: plan,
        firstPageDuration: const Duration(milliseconds: 400),
        fullPlanDuration: const Duration(milliseconds: 2001),
      ),
      NovelReaderPaginationPerformanceFallbackReason.fullPlanBudgetExceeded,
    );
  });

  test('mixed content uses the wider renderer budget', () {
    final plan = _plan(complexBlockCount: 1);

    expect(
      policy.evaluate(
        plan: plan,
        firstPageDuration: const Duration(milliseconds: 700),
        fullPlanDuration: const Duration(seconds: 4),
      ),
      isNull,
    );
    expect(
      policy.evaluate(
        plan: plan,
        firstPageDuration: const Duration(milliseconds: 801),
      ),
      NovelReaderPaginationPerformanceFallbackReason.firstPageBudgetExceeded,
    );
  });

  test('disabled policy never requests a fallback', () {
    const disabled = NovelReaderPaginationPerformancePolicy(
      enforceBudgets: false,
    );

    expect(
      disabled.evaluate(
        plan: _plan(complexBlockCount: 1),
        firstPageDuration: const Duration(minutes: 1),
        fullPlanDuration: const Duration(minutes: 2),
      ),
      isNull,
    );
  });

  test('diagnostics expose safe runs, cancellations and cache hit rate', () {
    final diagnostics = NovelReaderPaginationDiagnostics(
      episodeId: 'episode',
      paginationKey: 'layout',
      pageCount: 8,
      layoutDuration: const Duration(milliseconds: 300),
      reflowCount: 1,
      unknownImageDimensionCount: 0,
      overflowPageCount: 0,
      cacheHit: false,
      flowUnitCount: 4,
      measurementCount: 4,
      measurementCacheHitCount: 3,
      safeTextRunCount: 12,
      cancelledPlanCount: 2,
      safeTextFallbackReasonCounts:
          const <NovelReaderSafeTextFallbackReason, int>{
            NovelReaderSafeTextFallbackReason.rendererMismatch: 1,
          },
    );

    expect(diagnostics.measurementCacheHitRate, 0.75);
    expect(diagnostics.toString(), contains('safeRuns=12'));
    expect(diagnostics.toString(), contains('cancelledPlans=2'));
    expect(diagnostics.toString(), contains('rendererMismatch'));
  });
}

NovelReaderPaginationPlan _plan({int complexBlockCount = 0}) {
  const key = NovelReaderPaginationKey(
    episodeId: 'episode',
    contentHash: 'content',
    viewportWidthPx: 320,
    viewportHeightPx: 600,
    typographySignature: 'typography',
    themeSignature: 'theme',
    imageDimensionRevision: 1,
    rendererRevision: 3,
  );
  return NovelReaderPaginationPlan(
    key: key,
    episodeId: key.episodeId,
    pages: const [],
    complexBlockCount: complexBlockCount,
  );
}
