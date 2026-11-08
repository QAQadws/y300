import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  test('visits distinguish first-frame revisits from eventual success', () {
    var now = Duration.zero;
    final metrics = ForumHtmlImageVisibilityMetrics(elapsed: () => now);
    void sample(bool visible, bool painted) => metrics.observe(
      'image',
      visible: visible,
      painted: painted,
      failed: false,
    );
    sample(true, true);
    sample(true, true);
    sample(false, false);
    sample(true, false);
    now += const Duration(milliseconds: 40);
    sample(true, true);
    sample(false, false);
    sample(true, true);

    final values = metrics.snapshot.values;
    expect(values['entries'], 3);
    expect(values['revisitEntries'], 2);
    expect(values['revisitFirstFrameHits'], 1);
    expect(values['revisitFirstFrameHitRatio'], 0.5);
    expect(values['completed'], 3);
    expect(values['successfulWaits'], {
      'recentSamples': 3,
      'p50Ms': 0.0,
      'p95Ms': 40.0,
      'p99Ms': 40.0,
    });
  });

  test('failures, abandonment and pending waits are separate outcomes', () {
    var now = Duration.zero;
    final metrics = ForumHtmlImageVisibilityMetrics(elapsed: () => now);
    metrics.observe('failed', visible: true, painted: false, failed: false);
    now += const Duration(milliseconds: 100);
    metrics.observe('failed', visible: true, painted: false, failed: true);
    metrics.observe('failed', visible: false, painted: false, failed: false);
    metrics.observe('abandoned', visible: true, painted: false, failed: false);
    now += const Duration(milliseconds: 200);
    metrics.retire('abandoned');
    metrics.observe('pending', visible: true, painted: false, failed: false);
    now += const Duration(milliseconds: 300);
    final snapshot = metrics.snapshot.values;
    expect(snapshot['failed'], 1);
    expect(snapshot['abandoned'], 1);
    expect(snapshot['pending'], 1);
    expect(snapshot['oldestPendingWaitMs'], 300);
    expect(snapshot['completed'], 0);
    expect((snapshot['failureWaits'] as Map)['p95Ms'], 100);
    expect((snapshot['abandonedWaits'] as Map)['p95Ms'], 200);
    expect((snapshot['successfulWaits'] as Map)['p95Ms'], isNull);

    metrics.close();
    final closed = metrics.snapshot.toJson();
    expect(closed['abandoned'], 2);
    expect(closed['pending'], 0);
    metrics.observe('pending', visible: true, painted: true, failed: false);
    expect(metrics.snapshot.toJson(), closed);
  });

  test('failed or only prepared images do not seed revisit history', () {
    final metrics = ForumHtmlImageVisibilityMetrics();
    metrics.observe('image', visible: true, painted: false, failed: true);
    metrics.retire('image');
    metrics.observe('image', visible: true, painted: true, failed: false);
    expect(metrics.snapshot.values['revisitEntries'], 0);
    expect(metrics.snapshot.values['completed'], 1);
  });

  test('history eviction and recent wait samples have explicit bounds', () {
    var now = Duration.zero;
    final metrics = ForumHtmlImageVisibilityMetrics(
      historyCapacity: 2,
      waitSampleCapacity: 2,
      elapsed: () => now,
    );
    for (var i = 1; i <= 3; i++) {
      metrics.observe(i, visible: true, painted: false, failed: false);
      now += Duration(milliseconds: i * 10);
      metrics.observe(i, visible: true, painted: true, failed: false);
      metrics.retire(i);
    }
    final values = metrics.snapshot.values;
    expect(values['historyEntries'], 2);
    expect(values['historyEvictions'], 1);
    expect(values['completed'], 3);
    expect(values['successfulWaits'], {
      'recentSamples': 2,
      'p50Ms': 20.0,
      'p95Ms': 30.0,
      'p99Ms': 30.0,
    });
    metrics.observe(1, visible: true, painted: true, failed: false);
    metrics.retire(1);
    metrics.observe(3, visible: true, painted: true, failed: false);
    expect(metrics.snapshot.values['revisitEntries'], 1);
  });

  test('active capacity and numeric-only immutable exports stay bounded', () {
    final metrics = ForumHtmlImageVisibilityMetrics(activeCapacity: 1);
    metrics.observe(
      'https://private.invalid/a',
      visible: true,
      painted: false,
      failed: false,
    );
    metrics.observe('other', visible: true, painted: false, failed: false);
    final snapshot = metrics.snapshot;
    expect(snapshot.values['pending'], 1);
    expect(snapshot.values['droppedObservations'], 1);
    expect(jsonEncode(snapshot), isNot(contains('private.invalid')));
    expect(() => snapshot.values['entries'] = 42, throwsUnsupportedError);
  });
}
