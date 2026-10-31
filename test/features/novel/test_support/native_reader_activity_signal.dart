import 'package:flutter/foundation.dart';

/// Exposes listener lifetime and redundant lifecycle events to integration tests.
final class NativeReaderActivitySignal extends ValueNotifier<bool> {
  NativeReaderActivitySignal(super.value);

  bool get isObserved => hasListeners;
  void repeat() => notifyListeners();
}
