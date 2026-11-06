import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_main_page_profile_timings.dart';

void main() {
  test('late batches belong to their original vsync interval', () {
    final frames = ProfileFrameWindows();
    frames.begin('open', 100);
    frames.end(200);
    frames.begin('turn', 200);
    frames.end(300);
    void add(int timestamp, int build) => frames.add(
      vsyncUs: timestamp,
      buildUs: build,
      rasterUs: 50,
      totalUs: 100,
    );
    add(100, 999); // Outside the open interval.
    add(150, 20);
    add(200, 30); // Last frame of opening, not first frame of the turn.
    add(250, 40);
    add(301, 999); // Outside the turn interval.
    final [open, turn] = frames.summaries(frameBudgetUs: 25).toList();
    expect(open['frameCount'], 2);
    expect(open['buildOverBudget'], 1);
    expect(open['buildUs'], {'count': 2, 'p50': 20, 'p95': 30, 'max': 30});
    expect(turn['frameCount'], 1);
    expect(turn['buildUs'], {'count': 1, 'p50': 40, 'p95': 40, 'max': 40});
  });

  test('early timing delivery is retained when its window closes', () {
    final frames = ProfileFrameWindows();
    frames.begin('open', 10);
    frames.add(vsyncUs: 20, buildUs: 1, rasterUs: 2, totalUs: 3);
    frames.end(20);
    expect(frames.summaries(frameBudgetUs: 10).single['frameCount'], 1);
    expect(() => frames.end(30), throwsStateError);
    expect(() => frames.begin('overlap', 19), throwsStateError);
  });

  test('no delivered samples remains missing rather than zero duration', () {
    final frames = ProfileFrameWindows();
    frames.begin('empty', 10);
    frames.end(20);
    final empty = frames.summaries(frameBudgetUs: 10).single;
    expect(empty['windowsWithoutFrames'], 1);
    expect(empty['buildUs'], {
      'count': 0,
      'p50': null,
      'p95': null,
      'max': null,
    });
  });

  test(
    'turn groups merge only attributed frames and report individual stalls',
    () {
      final frames = ProfileFrameWindows();
      frames.begin('7/turn-0', 0, reportGroup: '7/turns');
      frames.end(20);
      frames.begin('7/turn-1', 30, reportGroup: '7/turns');
      frames.end(40);
      frames.begin('7/turn-2', 50, reportGroup: '7/turns');
      frames.end(60);
      void add(int vsyncUs, int buildUs, int totalUs) => frames.add(
        vsyncUs: vsyncUs,
        buildUs: buildUs,
        rasterUs: 5,
        totalUs: totalUs,
      );

      for (var i = 1; i <= 19; i++) {
        add(i, i, 30);
      }
      add(25, 9999, 90000); // An idle gap, outside all turn windows.
      add(35, 100, 55000);

      final turns = frames.summaries(frameBudgetUs: 16).single;
      expect(turns['phase'], '7/turns');
      expect(turns['windowCount'], 3);
      expect(turns['windowsWithoutFrames'], 1);
      expect(turns['frameCount'], 20);
      expect(turns['buildOverBudget'], 4);
      expect(turns['buildUs'], {'count': 20, 'p50': 10, 'p95': 19, 'max': 100});
      expect(frames.slowFrames().single, {
        'phase': '7/turn-1',
        'vsyncUs': 35,
        'buildUs': 100,
        'rasterUs': 5,
        'totalUs': 55000,
      });
    },
  );
}
