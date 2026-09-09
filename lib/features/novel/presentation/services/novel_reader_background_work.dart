import 'dart:isolate';

/// Runs large, data-only chapter transforms off the UI isolate. Callbacks must
/// capture only their inputs, never a widget, provider, channel or layout object.
abstract final class NovelReaderBackgroundWork {
  static const int codeUnitThreshold = 12000;

  static Future<T> run<T>({
    required int codeUnits,
    required T Function() transform,
  }) {
    if (codeUnits < codeUnitThreshold) {
      return Future<T>.sync(transform);
    }
    return Isolate.run(transform, debugName: 'novel-chapter-transform');
  }
}
