import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
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
      recorder.recordContinuousImage(
        ContinuousImageDiagnosticEvent(
          time: DateTime(2026),
          type: ContinuousImageDiagnosticEventType.imageDecodeResolved,
          itemId: 'item-1',
          ownerId: 'thread:100',
          index: 1,
          source: ContinuousImageSourceKind.threadPostImage.name,
          aspectRatio: 0.5,
          width: 800,
          height: 1600,
          message: 'decoded',
        ),
      );

      final events = recorder.snapshot();
      expect(events, hasLength(2));
      expect(events.first.type, ThreadDetailDiagnosticEventType.scrollAnimate);
      expect(events.last.type, ThreadDetailDiagnosticEventType.continuousImage);
      expect(recorder.exportText(), contains('scroll top'));
      expect(recorder.exportText(), contains('continuous=imageDecodeResolved'));
      expect(recorder.exportText(), contains('size=800x1600'));

      recorder.clear();
      expect(recorder.snapshot(), isEmpty);
    });
  });
}
