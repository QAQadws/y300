import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_image_visibility_diagnostics.dart';

void main() {
  test('disabled diagnostics expose no observer and emit no logs', () {
    final logs = <String>[];
    final diagnostics = ThreadImageVisibilityDiagnostics(
      enabled: false,
      writeLog: logs.add,
    );
    expect(diagnostics.observer, isNull);
    diagnostics.observe('image', visible: true, painted: true, failed: false);
    diagnostics.reset();
    diagnostics.dispose();
    expect(logs, isEmpty);
  });

  test('source reset closes pending visits and starts fresh history', () {
    final logs = <String>[];
    final diagnostics = ThreadImageVisibilityDiagnostics(
      enabled: true,
      writeLog: logs.add,
    );
    diagnostics.observe(
      'private-source',
      visible: true,
      painted: true,
      failed: false,
    );
    diagnostics.retire('private-source');
    diagnostics.observe(
      'pending',
      visible: true,
      painted: false,
      failed: false,
    );
    diagnostics.reset();
    final previous = _snapshot(logs.single);
    expect(previous['completed'], 1);
    expect(previous['abandoned'], 1);
    expect(previous['pending'], 0);
    expect(logs.single, isNot(contains('private-source')));
    diagnostics.observe(
      'private-source',
      visible: true,
      painted: true,
      failed: false,
    );
    diagnostics.checkpoint('inactive');
    expect(_snapshot(logs.last)['entries'], 1);
    expect(_snapshot(logs.last)['revisitEntries'], 0);
    diagnostics.dispose();
    final count = logs.length;
    diagnostics.observe('late', visible: true, painted: true, failed: false);
    diagnostics.checkpoint('late');
    diagnostics.reset();
    expect(logs, hasLength(count));
    expect(diagnostics.observer, isNull);
  });

  test('logging failure cannot stop disposal', () {
    final diagnostics = ThreadImageVisibilityDiagnostics(
      enabled: true,
      writeLog: (_) => throw StateError('sink unavailable'),
    );
    diagnostics.observe('image', visible: true, painted: false, failed: false);
    diagnostics.dispose();
    expect(diagnostics.observer, isNull);
  });
}

Map<String, dynamic> _snapshot(String log) =>
    jsonDecode(log.substring(log.indexOf('{'))) as Map<String, dynamic>;
