import 'package:y300/features/thread/domain/models/thread_detail_diagnostic_event.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

abstract class ThreadDetailDiagnosticRecorder
    implements ContinuousImageDiagnosticRecorder {
  @override
  bool get enabled;

  List<ThreadDetailDiagnosticEvent> snapshot();

  String exportText();

  void clear();

  void record({
    required ThreadDetailDiagnosticEventType type,
    String? entryKey,
    String? pid,
    double? scrollOffset,
    required String message,
  });
}

class InMemoryThreadDetailDiagnosticRecorder
    implements ThreadDetailDiagnosticRecorder {
  InMemoryThreadDetailDiagnosticRecorder({
    this.enabled = false,
    int capacity = 240,
  }) : _capacity = capacity;

  final int _capacity;
  final List<ThreadDetailDiagnosticEvent> _events =
      <ThreadDetailDiagnosticEvent>[];

  @override
  bool enabled;

  set enabledState(bool value) {
    enabled = value;
  }

  @override
  List<ThreadDetailDiagnosticEvent> snapshot() {
    return List<ThreadDetailDiagnosticEvent>.unmodifiable(_events);
  }

  @override
  String exportText() {
    return _events.map((event) => event.toLogLine()).join('\n');
  }

  @override
  void clear() {
    _events.clear();
  }

  @override
  void record({
    required ThreadDetailDiagnosticEventType type,
    String? entryKey,
    String? pid,
    double? scrollOffset,
    required String message,
  }) {
    if (!enabled) {
      return;
    }
    _events.add(
      ThreadDetailDiagnosticEvent(
        time: DateTime.now(),
        type: type,
        entryKey: entryKey,
        pid: pid,
        scrollOffset: scrollOffset,
        message: message,
      ),
    );
    if (_events.length > _capacity) {
      _events.removeRange(0, _events.length - _capacity);
    }
  }

  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) {
    record(
      type: ThreadDetailDiagnosticEventType.continuousImage,
      entryKey: event.itemId,
      scrollOffset: null,
      message: event.toLogFields(),
    );
  }
}

class NoopThreadDetailDiagnosticRecorder
    implements ThreadDetailDiagnosticRecorder {
  const NoopThreadDetailDiagnosticRecorder();

  @override
  bool get enabled => false;

  @override
  void clear() {}

  @override
  String exportText() => '';

  @override
  void record({
    required ThreadDetailDiagnosticEventType type,
    String? entryKey,
    String? pid,
    double? scrollOffset,
    required String message,
  }) {}

  @override
  List<ThreadDetailDiagnosticEvent> snapshot() =>
      const <ThreadDetailDiagnosticEvent>[];

  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) {}
}
