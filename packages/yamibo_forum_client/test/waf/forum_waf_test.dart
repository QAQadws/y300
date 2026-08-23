import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test('verification probes only after cookie sync completes', () async {
    final events = <String>[];
    final service = ForumWafVerificationService(
      syncCookies: (uri) async => events.add('sync'),
      probe: ({required uri, required userAgent}) async {
        events.add('probe');
        return ForumWafClearance.cleared;
      },
    );
    expect(
      await service.verify(
        uri: Uri.parse('https://bbs.yamibo.com/'),
        userAgent: 'test',
      ),
      ForumWafClearance.cleared,
    );
    expect(events, <String>['sync', 'probe']);
  });

  test('concurrent WAF recoveries share one in-flight attempt', () async {
    final gate = Completer<void>();
    var calls = 0;
    final coordinator = ForumWafCoordinator();
    coordinator.attach((request) async {
      calls++;
      await gate.future;
      return ForumWafRecoveryResult.verified;
    });
    final request = ForumWafRecoveryRequest(
      uri: Uri.parse('https://bbs.yamibo.com/'),
      method: 'GET',
      evidence: ForumWafEvidence.scriptBody,
      userAgent: 'test',
    );
    final first = coordinator.recover(request);
    final second = coordinator.recover(request);
    gate.complete();
    expect(await first, ForumWafRecoveryResult.verified);
    expect(await second, ForumWafRecoveryResult.verified);
    expect(calls, 1);
  });
}
