import 'package:y300/features/history/domain/models/history_models.dart';

enum HistoryDiagnosticOutcome { success, failure }

abstract interface class HistoryDiagnosticRecorder {
  void recordWrite({
    required HistoryTargetType targetType,
    required HistoryVisitSurface surface,
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    String? errorType,
  });

  void recordQuery({
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    required bool searching,
    int? itemCount,
    bool? hasMore,
    String? errorType,
  });

  void recordSkip({
    required HistoryVisitSurface surface,
    required String reason,
  });
}

class NoopHistoryDiagnosticRecorder implements HistoryDiagnosticRecorder {
  const NoopHistoryDiagnosticRecorder();

  @override
  void recordWrite({
    required HistoryTargetType targetType,
    required HistoryVisitSurface surface,
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    String? errorType,
  }) {}

  @override
  void recordQuery({
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    required bool searching,
    int? itemCount,
    bool? hasMore,
    String? errorType,
  }) {}

  @override
  void recordSkip({
    required HistoryVisitSurface surface,
    required String reason,
  }) {}
}
