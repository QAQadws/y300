import 'dart:math' as math;

/// Uses engine vsync time, never the time a batched timing callback arrived.
final class ProfileFrameWindows {
  final _windows = <_ProfileFrameWindow>[];
  _ProfileFrameWindow? _active;
  int _samples = 0;
  bool overflowed = false;
  static const maxSamples = 100000;

  void begin(String label, int startExclusiveUs, {String? reportGroup}) {
    if (_active != null ||
        (_windows.isNotEmpty &&
            startExclusiveUs < _windows.last.endInclusiveUs!)) {
      throw StateError('Overlapping profile frame windows');
    }
    final window = _ProfileFrameWindow(
      label,
      startExclusiveUs,
      reportGroup ?? label,
    );
    _windows.add(window);
    _active = window;
  }

  void end(int endInclusiveUs) {
    final window = _active;
    if (window == null || endInclusiveUs < window.startExclusiveUs) {
      throw StateError('Invalid profile frame interval');
    }
    window.endInclusiveUs = endInclusiveUs;
    _active = null;
    // Timings may arrive before the post-frame continuation closes this window.
    window.frames.removeWhere((frame) => frame.vsyncUs > endInclusiveUs);
  }

  void add({
    required int vsyncUs,
    required int buildUs,
    required int rasterUs,
    required int totalUs,
  }) {
    var low = 0;
    var high = _windows.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_windows[middle].startExclusiveUs < vsyncUs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return;
    final window = _windows[low - 1];
    if (window.endInclusiveUs case final end? when vsyncUs > end) return;
    if (++_samples > maxSamples) {
      overflowed = true;
      return;
    }
    window.frames.add((
      vsyncUs: vsyncUs,
      buildUs: buildUs,
      rasterUs: rasterUs,
      totalUs: totalUs,
    ));
  }

  Iterable<Map<String, Object>> summaries({
    required double frameBudgetUs,
  }) sync* {
    final groups = <String, List<_ProfileFrameWindow>>{};
    for (final window in _windows) {
      (groups[window.reportGroup] ??= []).add(window);
    }
    for (final entry in groups.entries) {
      final windows = entry.value;
      // Merge raw samples only after attribution. The gaps between turn
      // commands remain outside the group, and empty commands stay visible.
      final frames = windows.expand((window) => window.frames).toList();
      yield {
        'phase': entry.key,
        'windowCount': windows.length,
        'windowsWithoutFrames': windows.where((w) => w.frames.isEmpty).length,
        'frameCount': frames.length,
        'buildUs': profileDistribution(frames.map((frame) => frame.buildUs)),
        'rasterUs': profileDistribution(frames.map((frame) => frame.rasterUs)),
        'totalUs': profileDistribution(frames.map((frame) => frame.totalUs)),
        'buildOverBudget': frames
            .where((frame) => frame.buildUs > frameBudgetUs)
            .length,
        'rasterOverBudget': frames
            .where((frame) => frame.rasterUs > frameBudgetUs)
            .length,
        'totalOverBudget': frames
            .where((frame) => frame.totalUs > frameBudgetUs)
            .length,
      };
    }
  }

  Iterable<Map<String, Object>> slowFrames() sync* {
    for (final window in _windows) {
      for (final frame in window.frames) {
        if (frame.totalUs <= 50000) continue;
        yield {
          'phase': window.label,
          'vsyncUs': frame.vsyncUs,
          'buildUs': frame.buildUs,
          'rasterUs': frame.rasterUs,
          'totalUs': frame.totalUs,
        };
      }
    }
  }
}

final class _ProfileFrameWindow {
  _ProfileFrameWindow(this.label, this.startExclusiveUs, this.reportGroup);

  final String label;
  final int startExclusiveUs;
  final String reportGroup;
  int? endInclusiveUs;
  final frames = <({int vsyncUs, int buildUs, int rasterUs, int totalUs})>[];
}

Map<String, Object?> profileDistribution(Iterable<int> input) {
  final values = input.toList()..sort();
  int? percentile(double fraction) => values.isEmpty
      ? null
      : values[math.max(0, (values.length * fraction).ceil() - 1)];
  return {
    'count': values.length,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'max': values.isEmpty ? null : values.last,
  };
}
