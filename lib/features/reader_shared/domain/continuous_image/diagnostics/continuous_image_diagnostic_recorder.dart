import 'continuous_image_diagnostic_event.dart';

abstract class ContinuousImageDiagnosticRecorder {
  bool get enabled;

  void recordContinuousImage(ContinuousImageDiagnosticEvent event);
}

class NoopContinuousImageDiagnosticRecorder
    implements ContinuousImageDiagnosticRecorder {
  const NoopContinuousImageDiagnosticRecorder();

  @override
  bool get enabled => false;

  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) {}
}
