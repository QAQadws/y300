import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

void main() {
  test(
    'request budgets are enabled independently of content classification',
    () {
      const policy = NovelReaderPaginationPerformancePolicy();

      expect(policy.enforceBudgets, isTrue);
      expect(policy.targetPageWait, const Duration(seconds: 5));
      expect(policy.backgroundIdle, const Duration(seconds: 2));
    },
  );

  test('hosts can configure target wait and background idle separately', () {
    const policy = NovelReaderPaginationPerformancePolicy(
      targetPageWait: Duration(milliseconds: 50),
      backgroundIdle: Duration(milliseconds: 100),
      enforceBudgets: false,
    );

    expect(policy.targetPageWait, const Duration(milliseconds: 50));
    expect(policy.backgroundIdle, const Duration(milliseconds: 100));
    expect(policy.enforceBudgets, isFalse);
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
