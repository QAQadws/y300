import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/data/services/debug_history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';

void main() {
  test('debug diagnostics contain only the bounded metadata contract', () {
    final lines = <String>[];
    final recorder = DebugHistoryDiagnosticRecorder(
      structuredRecorder: const NoopSyncDiagnosticRecorder(),
      lineWriter: lines.add,
    );

    recorder.recordWrite(
      targetType: HistoryTargetType.thread,
      surface: HistoryVisitSurface.threadNative,
      outcome: HistoryDiagnosticOutcome.failure,
      elapsedMs: 12,
      errorType: 'StateError',
    );
    recorder.recordQuery(
      outcome: HistoryDiagnosticOutcome.success,
      elapsedMs: 3,
      searching: true,
      itemCount: 50,
      hasMore: true,
    );
    recorder.recordSkip(
      surface: HistoryVisitSurface.threadWebView,
      reason: 'duplicate_target',
    );

    expect(lines, hasLength(3));
    expect(lines.first, contains('targetType=thread'));
    expect(lines[1], contains('itemCount=50'));
    expect(lines.last, contains('reason=duplicate_target'));
    expect(lines.join('\n'), isNot(contains('title=')));
    expect(lines.join('\n'), isNot(contains('url=')));
    expect(lines.join('\n'), isNot(contains('targetId=')));
  });
}
