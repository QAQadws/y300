import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_main_page_profile_timings.dart';

void main() {
  test('late batches belong to their original vsync interval', () {
    final frames = ProfileFrameWindows();
    final open = frames.begin('open', 100);
    frames.end(200);
    final turn = frames.begin('turn', 200);
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
    expect(open.toJson(frameBudgetUs: 25)['frameCount'], 2);
    expect(open.toJson(frameBudgetUs: 25)['buildOverBudget'], 1);
    expect(open.toJson(frameBudgetUs: 25)['buildUs'], {
      'count': 2,
      'p50': 20,
      'p95': 30,
      'max': 30,
    });
    expect(turn.toJson(frameBudgetUs: 100)['frameCount'], 1);
    expect(turn.toJson(frameBudgetUs: 100)['buildUs'], {
      'count': 1,
      'p50': 40,
      'p95': 40,
      'max': 40,
    });
  });

  test('early timing delivery is retained when its window closes', () {
    final frames = ProfileFrameWindows();
    final window = frames.begin('open', 10);
    frames.add(vsyncUs: 20, buildUs: 1, rasterUs: 2, totalUs: 3);
    frames.end(20);
    expect(window.toJson(frameBudgetUs: 10)['frameCount'], 1);
    expect(() => frames.end(30), throwsStateError);
    expect(() => frames.begin('overlap', 19), throwsStateError);
  });

  test('no delivered samples remains missing rather than zero duration', () {
    final frames = ProfileFrameWindows();
    final window = frames.begin('empty', 10);
    frames.end(20);
    expect(window.toJson(frameBudgetUs: 10)['buildUs'], {
      'count': 0,
      'p50': null,
      'p95': null,
      'max': null,
    });
  });
}
