import 'package:flutter/foundation.dart';

/// Lightweight shelf performance tracing for debug/profile builds.
///
/// This keeps Milestone A observable without introducing a logging dependency
/// into adapters or widgets. Release builds skip all work behind [kReleaseMode].
class ShelfPerfTrace {
  ShelfPerfTrace({required this.name}) : _total = Stopwatch() {
    if (!kReleaseMode) {
      _total.start();
    }
  }

  final String name;
  final Stopwatch _total;
  final Map<String, int> _durationsMs = <String, int>{};
  final Map<String, Object> _metrics = <String, Object>{};

  Future<T> measure<T>(String label, Future<T> Function() action) async {
    if (kReleaseMode) {
      return action();
    }
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      _durationsMs[label] = stopwatch.elapsedMilliseconds;
    }
  }

  void metric(String key, Object value) {
    if (kReleaseMode) {
      return;
    }
    _metrics[key] = value;
  }

  void finish() {
    if (kReleaseMode) {
      return;
    }
    _total.stop();
    final parts = <String>[
      'total=${_total.elapsedMilliseconds}ms',
      for (final entry in _durationsMs.entries) '${entry.key}=${entry.value}ms',
      for (final entry in _metrics.entries) '${entry.key}=${entry.value}',
    ];
    debugPrint('[ShelfPerfTrace][$name] ${parts.join(' ')}');
  }
}
