import 'dart:math' as math;

/// Uses engine vsync time, never the time a batched timing callback arrived.
final class ProfileFrameWindows {
  final _windows = <ProfileFrameWindow>[];
  ProfileFrameWindow? _active;
  int _samples = 0;
  bool overflowed = false;
  static const maxSamples = 100000;

  List<ProfileFrameWindow> get windows => List.unmodifiable(_windows);

  ProfileFrameWindow begin(String label, int startExclusiveUs) {
    if (_active != null ||
        (_windows.isNotEmpty &&
            startExclusiveUs < _windows.last.endInclusiveUs!)) {
      throw StateError('Overlapping profile frame windows');
    }
    final window = ProfileFrameWindow._(label, startExclusiveUs);
    _windows.add(window);
    _active = window;
    return window;
  }

  void end(int endInclusiveUs) {
    final window = _active;
    if (window == null || endInclusiveUs < window.startExclusiveUs) {
      throw StateError('Invalid profile frame interval');
    }
    window.endInclusiveUs = endInclusiveUs;
    _active = null;
    // Timings may arrive before the post-frame continuation closes this window.
    window._frames.removeWhere((frame) => frame.vsyncUs > endInclusiveUs);
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
    window._frames.add((
      vsyncUs: vsyncUs,
      buildUs: buildUs,
      rasterUs: rasterUs,
      totalUs: totalUs,
    ));
  }
}

final class ProfileFrameWindow {
  ProfileFrameWindow._(this.label, this.startExclusiveUs);
  final String label;
  final int startExclusiveUs;
  int? endInclusiveUs;
  final _frames = <({int vsyncUs, int buildUs, int rasterUs, int totalUs})>[];

  Map<String, Object?> toJson({required double frameBudgetUs}) => {
    'phase': label,
    'startExclusiveVsyncUs': startExclusiveUs,
    'endInclusiveVsyncUs': endInclusiveUs,
    'frameCount': _frames.length,
    'buildUs': profileDistribution(_frames.map((frame) => frame.buildUs)),
    'rasterUs': profileDistribution(_frames.map((frame) => frame.rasterUs)),
    'totalUs': profileDistribution(_frames.map((frame) => frame.totalUs)),
    'buildOverBudget': _frames
        .where((frame) => frame.buildUs > frameBudgetUs)
        .length,
    'rasterOverBudget': _frames
        .where((frame) => frame.rasterUs > frameBudgetUs)
        .length,
    'totalOverBudget': _frames
        .where((frame) => frame.totalUs > frameBudgetUs)
        .length,
  };
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
