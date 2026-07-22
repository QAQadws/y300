import 'package:flutter/foundation.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';

typedef HistoryDiagnosticLineWriter = void Function(String line);

class DebugHistoryDiagnosticRecorder implements HistoryDiagnosticRecorder {
  DebugHistoryDiagnosticRecorder({HistoryDiagnosticLineWriter? lineWriter})
    : _lineWriter = lineWriter ?? debugPrint;

  final HistoryDiagnosticLineWriter _lineWriter;

  @override
  void recordWrite({
    required HistoryTargetType targetType,
    required HistoryVisitSurface surface,
    required HistoryDiagnosticOutcome outcome,
    required int elapsedMs,
    String? errorType,
  }) {
    _record(
      event: outcome == HistoryDiagnosticOutcome.success
          ? 'write_succeeded'
          : 'write_failed',
      fields: <String, Object?>{
        'targetType': targetType.name,
        'surface': surface.name,
        'elapsedMs': elapsedMs,
        'errorType': ?errorType,
      },
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
    _record(
      event: outcome == HistoryDiagnosticOutcome.success
          ? 'query_succeeded'
          : 'query_failed',
      fields: <String, Object?>{
        'elapsedMs': elapsedMs,
        'searching': searching,
        'itemCount': ?itemCount,
        'hasMore': ?hasMore,
        'errorType': ?errorType,
      },
    );
  }

  @override
  void recordSkip({
    required HistoryVisitSurface surface,
    required String reason,
  }) {
    _record(
      event: 'visit_skipped',
      fields: <String, Object?>{'surface': surface.name, 'reason': reason},
    );
  }

  void _record({required String event, required Map<String, Object?> fields}) {
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    _lineWriter('[History][diagnostic][$event] $details');
  }
}
