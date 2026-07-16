import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_use_cases.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';
import 'package:y300/features/history/domain/services/record_history_visit_use_case.dart';

import '../test_support/history_test_support.dart';

void main() {
  test(
    'write and query diagnostics expose outcomes, latency, and counts',
    () async {
      final repository = MemoryHistoryRepository();
      final diagnostics = _RecordingHistoryDiagnostics();
      final record = RecordHistoryVisitUseCase(
        repository: repository,
        normalizer: const HistoryVisitDraftNormalizer(),
        clock: const _FixedClock(),
        diagnosticRecorder: diagnostics,
      );
      final query = QueryHistoryUseCase(
        repository: repository,
        normalizer: const HistoryVisitDraftNormalizer(),
        diagnosticRecorder: diagnostics,
      );
      addTearDown(repository.dispose);

      await record.record(
        HistoryVisitDraft(
          target: HistoryTargetKey(type: HistoryTargetType.thread, id: '100'),
          surface: HistoryVisitSurface.threadNative,
          title: 'sensitive title must not enter diagnostics',
          canonicalUri: Uri(
            scheme: 'https',
            host: 'example.com',
            query: 'auth=secret',
          ),
        ),
      );
      final page = await query(const HistoryQuery(searchText: 'sensitive'));

      expect(page.items, hasLength(1));
      expect(
        diagnostics.writes.single.outcome,
        HistoryDiagnosticOutcome.success,
      );
      expect(diagnostics.writes.single.targetType, HistoryTargetType.thread);
      expect(
        diagnostics.writes.single.surface,
        HistoryVisitSurface.threadNative,
      );
      expect(diagnostics.writes.single.elapsedMs, greaterThanOrEqualTo(0));
      expect(
        diagnostics.queries.single.outcome,
        HistoryDiagnosticOutcome.success,
      );
      expect(diagnostics.queries.single.searching, isTrue);
      expect(diagnostics.queries.single.itemCount, 1);
      expect(diagnostics.queries.single.hasMore, isFalse);
    },
  );

  test('write and query failures are diagnosed and still rethrown', () async {
    final repository = _FailingHistoryRepository();
    final diagnostics = _RecordingHistoryDiagnostics();
    final record = RecordHistoryVisitUseCase(
      repository: repository,
      normalizer: const HistoryVisitDraftNormalizer(),
      clock: const _FixedClock(),
      diagnosticRecorder: diagnostics,
    );
    final query = QueryHistoryUseCase(
      repository: repository,
      normalizer: const HistoryVisitDraftNormalizer(),
      diagnosticRecorder: diagnostics,
    );
    addTearDown(repository.dispose);

    await expectLater(
      record.record(
        const HistoryVisitDraft(
          target: HistoryTargetKey(type: HistoryTargetType.comic, id: 'work'),
          surface: HistoryVisitSurface.comicDetail,
        ),
      ),
      throwsStateError,
    );
    await expectLater(query(const HistoryQuery()), throwsStateError);

    expect(diagnostics.writes.single.outcome, HistoryDiagnosticOutcome.failure);
    expect(diagnostics.writes.single.errorType, 'StateError');
    expect(
      diagnostics.queries.single.outcome,
      HistoryDiagnosticOutcome.failure,
    );
    expect(diagnostics.queries.single.errorType, 'StateError');
  });
}

class _FixedClock implements HistoryClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 7, 16);
}

class _FailingHistoryRepository extends MemoryHistoryRepository {
  @override
  Future<void> recordVisit(HistoryEntry candidate) {
    throw StateError('write failed');
  }

  @override
  Future<HistoryQueryPage> query(HistoryQuery query) {
    throw StateError('query failed');
  }
}

class _RecordingHistoryDiagnostics implements HistoryDiagnosticRecorder {
  final List<_WriteDiagnostic> writes = <_WriteDiagnostic>[];
  final List<_QueryDiagnostic> queries = <_QueryDiagnostic>[];
  final List<_SkipDiagnostic> skips = <_SkipDiagnostic>[];

  @override
  void recordWrite({
    required HistoryTargetType targetType,
    required HistoryVisitSurface surface,
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    String? errorType,
  }) {
    writes.add(
      _WriteDiagnostic(
        targetType: targetType,
        surface: surface,
        outcome: outcome,
        elapsedMs: elapsedMs,
        errorType: errorType,
      ),
    );
  }

  @override
  void recordQuery({
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    required bool searching,
    int? itemCount,
    bool? hasMore,
    String? errorType,
  }) {
    queries.add(
      _QueryDiagnostic(
        outcome: outcome,
        elapsedMs: elapsedMs,
        searching: searching,
        itemCount: itemCount,
        hasMore: hasMore,
        errorType: errorType,
      ),
    );
  }

  @override
  void recordSkip({
    required HistoryVisitSurface surface,
    required String reason,
  }) {
    skips.add(_SkipDiagnostic(surface: surface, reason: reason));
  }
}

class _WriteDiagnostic {
  const _WriteDiagnostic({
    required this.targetType,
    required this.surface,
    required this.outcome,
    required this.elapsedMs,
    required this.errorType,
  });

  final HistoryTargetType targetType;
  final HistoryVisitSurface surface;
  final HistoryDiagnosticOutcome outcome;
  final int elapsedMs;
  final String? errorType;
}

class _QueryDiagnostic {
  const _QueryDiagnostic({
    required this.outcome,
    required this.elapsedMs,
    required this.searching,
    required this.itemCount,
    required this.hasMore,
    required this.errorType,
  });

  final HistoryDiagnosticOutcome outcome;
  final int elapsedMs;
  final bool searching;
  final int? itemCount;
  final bool? hasMore;
  final String? errorType;
}

class _SkipDiagnostic {
  const _SkipDiagnostic({required this.surface, required this.reason});

  final HistoryVisitSurface surface;
  final String reason;
}
