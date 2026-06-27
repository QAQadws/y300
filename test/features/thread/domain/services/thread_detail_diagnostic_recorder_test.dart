import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/thread/domain/services/thread_detail_diagnostic_recorder.dart';

void main() {
  group('InMemoryThreadDetailDiagnosticRecorder', () {
    test('records and exports events only when enabled', () {
      final recorder = InMemoryThreadDetailDiagnosticRecorder(capacity: 2);

      recorder.record(
        type: ThreadDetailDiagnosticEventType.entryBuild,
        entryKey: 'ignored',
        message: 'disabled',
      );
      expect(recorder.snapshot(), isEmpty);

      recorder.enabledState = true;
      recorder.record(
        type: ThreadDetailDiagnosticEventType.entryBuild,
        entryKey: 'thread-post-body-p1',
        pid: 'p1',
        scrollOffset: 12.4,
        message: 'build postBody',
      );
      recorder.record(
        type: ThreadDetailDiagnosticEventType.renderPlanCreate,
        pid: 'p2',
        message: 'create render plan',
      );
      recorder.record(
        type: ThreadDetailDiagnosticEventType.scrollAnimate,
        message: 'scroll top',
      );

      final events = recorder.snapshot();
      expect(events, hasLength(2));
      expect(
        events.first.type,
        ThreadDetailDiagnosticEventType.renderPlanCreate,
      );
      expect(recorder.exportText(), contains('renderPlanCreate'));
      expect(recorder.exportText(), contains('scroll top'));

      recorder.clear();
      expect(recorder.snapshot(), isEmpty);
    });
  });
}
