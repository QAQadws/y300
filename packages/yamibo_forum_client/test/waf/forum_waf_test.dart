import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  group('header-only response policy', () {
    test('retains 405 and matches the exact normalized rate-limit rule', () {
      for (final status in [200, 403, 405, 503]) {
        final decision = ForumWafResponsePolicy.classify(
          statusCode: status,
          headers: const {
            'X-Tengine-Error': ['  DENIED BY HTTP_AUTO_RATELIMIT  '],
          },
        );
        expect(
          decision.evidence,
          status == 405
              ? ForumWafEvidence.httpStatus405
              : ForumWafEvidence.httpAutoRatelimit,
        );
      }
    });

    test('unknown and conflicting denials cannot start browser recovery', () {
      for (final values in [
        ['denied by req auth: expired timestamp'],
        ['denied by Referer ACL'],
        ['denied by IP ACL = blacklist'],
        ['denied by http_auto_ratelimit_extra'],
        ['denied by http_auto_ratelimit', 'denied by Referer ACL'],
      ]) {
        final decision = ForumWafResponsePolicy.classify(
          statusCode: 200,
          headers: {'x-tengine-error': values},
        );
        expect(decision, ForumWafResponseDecision.accessDenied);
        expect(decision.evidence, isNull);
      }
    });

    test('vendor name and unrelated headers do not prove a denial', () {
      for (final headers in <Map<String, List<String>>>[
        {},
        {
          'server': ['ESA'],
        },
        {
          'x-other': ['denied by http_auto_ratelimit'],
        },
        {
          'x-tengine-error': ['upstream timeout'],
        },
      ]) {
        expect(
          ForumWafResponsePolicy.classify(statusCode: 200, headers: headers),
          ForumWafResponseDecision.none,
        );
      }
      expect(
        ForumWafResponsePolicy.classify(statusCode: 405).evidence,
        ForumWafEvidence.httpStatus405,
      );
    });
  });

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
      evidence: ForumWafEvidence.httpStatus405,
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
