import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf.dart';

void main() {
  final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');

  test('syncs WebView cookies before probing native clearance', () async {
    final events = <String>[];
    final service = WafChallengeVerificationService(
      syncCookies: (_) async => events.add('sync'),
      probe: ({required uri, required userAgent}) async {
        events.add('probe:$userAgent');
        return WafChallengeClearance.cleared;
      },
    );

    expect(
      await service.verify(uri: uri, userAgent: 'test-agent'),
      WafChallengeClearance.cleared,
    );
    expect(events, <String>['sync', 'probe:test-agent']);
  });

  test(
    'does not hide a probe failure behind a successful WebView sync',
    () async {
      final service = WafChallengeVerificationService(
        syncCookies: (_) async {},
        probe: ({required uri, required userAgent}) async {
          return WafChallengeClearance.challenged;
        },
      );

      expect(
        await service.verify(uri: uri, userAgent: 'test-agent'),
        WafChallengeClearance.challenged,
      );
    },
  );

  test('propagates cookie sync errors so the page can retry', () async {
    var probeCalled = false;
    final service = WafChallengeVerificationService(
      syncCookies: (_) async => throw StateError('sync race'),
      probe: ({required uri, required userAgent}) async {
        probeCalled = true;
        return WafChallengeClearance.cleared;
      },
    );

    await expectLater(
      service.verify(uri: uri, userAgent: 'test-agent'),
      throwsA(isA<StateError>()),
    );
    expect(probeCalled, isFalse);
  });
}
