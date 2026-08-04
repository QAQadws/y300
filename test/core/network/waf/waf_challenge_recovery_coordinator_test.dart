import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/waf/waf.dart';

void main() {
  final request = WafChallengeRecoveryRequest(
    triggeringUri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
    method: 'GET',
    evidence: WafChallengeEvidence.scriptBody,
    userAgent: 'test-agent',
  );

  test(
    'reports unavailable while no foreground launcher is attached',
    () async {
      final coordinator = WafChallengeRecoveryCoordinator();
      expect(
        await coordinator.recover(request),
        WafChallengeRecoveryResult.unavailable,
      );
    },
  );

  test('deduplicates concurrent recovery requests', () async {
    final coordinator = WafChallengeRecoveryCoordinator();
    final completer = Completer<WafChallengeRecoveryResult>();
    var launchCount = 0;
    coordinator.attachLauncher((_) {
      launchCount += 1;
      return completer.future;
    });

    final first = coordinator.recover(request);
    final second = coordinator.recover(request);
    expect(launchCount, 1);

    completer.complete(WafChallengeRecoveryResult.verified);
    expect(await first, WafChallengeRecoveryResult.verified);
    expect(await second, WafChallengeRecoveryResult.verified);
  });

  test('only suppresses verified or cancelled attempts', () async {
    var now = DateTime.utc(2026, 8, 3);
    final coordinator = WafChallengeRecoveryCoordinator(
      retryCooldown: const Duration(seconds: 10),
      now: () => now,
    );
    var launchCount = 0;
    var nextResult = WafChallengeRecoveryResult.verified;
    coordinator.attachLauncher((_) async {
      launchCount += 1;
      return nextResult;
    });

    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.verified,
    );
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.coolingDown,
    );
    expect(launchCount, 1);

    now = now.add(const Duration(seconds: 11));
    nextResult = WafChallengeRecoveryResult.unavailable;
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.unavailable,
    );
    expect(launchCount, 2);

    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.unavailable,
    );
    expect(launchCount, 3);

    nextResult = WafChallengeRecoveryResult.cancelled;
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.cancelled,
    );
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.coolingDown,
    );
  });

  test('launcher failures are contained', () async {
    final coordinator = WafChallengeRecoveryCoordinator();
    coordinator.attachLauncher((_) => throw StateError('route failed'));
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.failed,
    );

    // A launch failure is infrastructure state, not a user cancellation;
    // the next request may try again immediately.
    expect(
      await coordinator.recover(request),
      WafChallengeRecoveryResult.failed,
    );
  });
}
