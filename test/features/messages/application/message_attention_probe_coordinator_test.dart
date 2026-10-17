import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_probe_coordinator.dart';
import 'package:y300/features/messages/application/message_attention_state.dart';

const MessageAttentionOwner _owner = (
  sessionOwner: (uid: '42', revision: 1),
  sourceGeneration: 3,
);
const _debounce = Duration(milliseconds: 750);

void main() {
  void run(
    void Function(_Harness harness) body, {
    MessageAttentionProbePolicy policy = const MessageAttentionProbePolicy(),
  }) {
    fakeAsync((async) {
      final harness = _Harness(async, policy);
      try {
        body(harness);
      } finally {
        harness.coordinator.dispose();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
      }
    });
  }

  test('default policy enables bounded event reads and disables polling', () {
    const policy = MessageAttentionProbePolicy();
    expect(policy.foregroundInterval, isNull);
    expect(policy.freshness, const Duration(minutes: 2));
    expect(policy.maximumAttempts, 2);
    expect(policy.retryDelay(1), const Duration(seconds: 30));
    expect(policy.retryDelay(2), const Duration(minutes: 1));
    expect(policy.retryDelay(100), const Duration(minutes: 5));
  });

  test('invalid timing policies fail before any work is scheduled', () {
    for (final policy in const [
      MessageAttentionProbePolicy(freshness: Duration.zero),
      MessageAttentionProbePolicy(coalesceDelay: Duration(seconds: -1)),
      MessageAttentionProbePolicy(initialRetryDelay: Duration.zero),
      MessageAttentionProbePolicy(maximumRetryDelay: Duration(seconds: 1)),
      MessageAttentionProbePolicy(maximumAttempts: 0),
      MessageAttentionProbePolicy(foregroundInterval: Duration(minutes: 1)),
    ]) {
      expect(
        () => MessageAttentionProbeCoordinator(
          policy: policy,
          probe: (_, _) async => true,
        ),
        throwsArgumentError,
      );
    }
  });

  test('construction, unverified identity and background do not probe', () {
    run((harness) {
      harness.coordinator.setEligibility(owner: null, foreground: true);
      harness.elapse(const Duration(hours: 1));
      harness.coordinator.setEligibility(owner: _owner, foreground: false);
      harness.elapse(const Duration(hours: 1));
      expect(harness.calls, isEmpty);
    });
  });

  test(
    'verified foreground activation defers once without periodic polling',
    () {
      run((harness) {
        harness.activate();
        expect(harness.calls, isEmpty);
        harness.elapse(const Duration(milliseconds: 749));
        expect(harness.calls, isEmpty);
        harness.elapse(const Duration(milliseconds: 1));
        expect(harness.calls, hasLength(1));
        expect(harness.coordinator.isProbing, isTrue);
        harness.finish(0, succeeded: true, sampleSequence: 1);
        expect(harness.coordinator.isProbing, isFalse);
        harness.elapse(const Duration(days: 1));
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test('normal fresh sampling cancels activation and resume duplicates', () {
    run((harness) {
      harness.activate();
      harness.sample(1);
      harness.elapse(_debounce);
      expect(harness.calls, isEmpty);
      harness.background();
      harness.elapse(const Duration(minutes: 1));
      harness.activate();
      harness.elapse(_debounce);
      expect(harness.calls, isEmpty);
    });
  });

  test('identical foreground rebuilds do not create opportunities', () {
    run((harness) {
      harness.activate();
      harness.elapse(_debounce);
      harness.finish(0, succeeded: true, sampleSequence: 1);
      harness.elapse(const Duration(minutes: 3));
      for (var i = 0; i < 10; ++i) {
        harness.activate();
      }
      harness.elapse(const Duration(minutes: 10));
      expect(harness.calls, hasLength(1));
    });
  });

  test('real foreground resume probes only when evidence is stale', () {
    run((harness) {
      harness.activate();
      harness.sample(1);
      harness.background();
      harness.elapse(const Duration(minutes: 2));
      harness.activate();
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(1));
    });
  });

  test('late samples cannot extend freshness', () {
    run((harness) {
      harness.activate();
      harness.sample(10);
      harness.elapse(const Duration(minutes: 1));
      harness.sample(9);
      harness.sample(10);
      harness.background();
      harness.elapse(const Duration(minutes: 1));
      harness.activate();
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(1));
    });
  });

  test(
    'successful consumption coalesces even when previous sample is fresh',
    () {
      run((harness) {
        harness.activate();
        harness.sample(1);
        harness.calibrate(2);
        harness.elapse(const Duration(milliseconds: 400));
        harness.calibrate(3);
        harness.elapse(const Duration(milliseconds: 749));
        expect(harness.calls, isEmpty);
        harness.elapse(const Duration(milliseconds: 1));
        expect(harness.calls, hasLength(1));
        harness.finish(0, succeeded: true, sampleSequence: 4);
        harness.elapse(const Duration(hours: 1));
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test('sample at the consumption barrier cannot cancel calibration', () {
    run((harness) {
      harness.activate();
      harness.sample(1);
      harness.calibrate(5);
      harness.sample(5);
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(1));
    });
  });

  test('complete ordinary sample after the barrier satisfies calibration', () {
    run((harness) {
      harness.activate();
      harness.calibrate(5);
      harness.sample(6);
      harness.elapse(_debounce);
      expect(harness.calls, isEmpty);
    });
  });

  test('a probe success alone cannot satisfy a consumption barrier', () {
    run((harness) {
      harness.activate();
      harness.calibrate(5);
      harness.elapse(_debounce);
      harness.finish(0, succeeded: true);
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(2));
      harness.finish(1, succeeded: true);
      harness.elapse(const Duration(days: 1));
      expect(harness.calls, hasLength(2));
    });
  });

  test('new consumption during a flight defers one newer calibration', () {
    run((harness) {
      harness.activate();
      harness.calibrate(5);
      harness.elapse(_debounce);
      harness.calibrate(7);
      harness.calibrate(8);
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(1));
      harness.finish(0, succeeded: true, sampleSequence: 6);
      harness.elapse(_debounce);
      expect(harness.calls, hasLength(2));
      harness.finish(1, succeeded: true, sampleSequence: 9);
      harness.elapse(const Duration(minutes: 10));
      expect(harness.calls, hasLength(2));
    });
  });

  test(
    'fresh callback inside a flight never cancels its cancellation token',
    () {
      run((harness) {
        harness.activate();
        harness.calibrate(1);
        harness.elapse(_debounce);
        harness.sample(2);
        expect(harness.calls.single.cancellation.isCancelled, isFalse);
        harness.finish(0, succeeded: true);
        harness.elapse(const Duration(minutes: 10));
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test(
    'fresh calibration before a late failed probe does not impose cooldown',
    () {
      run((harness) {
        harness.activate();
        harness.calibrate(1);
        harness.elapse(_debounce);
        harness.sample(2);
        harness.finish(0, succeeded: false);
        harness.calibrate(3);
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(2));
        harness.finish(1, succeeded: true, sampleSequence: 4);
        harness.elapse(const Duration(minutes: 1));
        expect(harness.calls, hasLength(2));
      });
    },
  );

  test(
    'new consumption during final retry has its own bounded opportunity',
    () {
      run((harness) {
        harness.activate();
        harness.calibrate(1);
        harness.elapse(_debounce);
        harness.finish(0, succeeded: false);
        harness.elapse(const Duration(seconds: 30));
        expect(harness.calls, hasLength(2));
        harness.calibrate(4);
        harness.finish(1, succeeded: false);
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(3));
        harness.finish(2, succeeded: false);
        harness.elapse(const Duration(seconds: 60));
        expect(harness.calls, hasLength(4));
        harness.finish(3, succeeded: true, sampleSequence: 5);
        harness.elapse(const Duration(hours: 1));
        expect(harness.calls, hasLength(4));
      });
    },
  );

  test(
    'failure and exceptions are silent and retry only within the opportunity',
    () {
      run((harness) {
        harness.activate();
        harness.elapse(_debounce);
        harness.calls[0].completion.completeError(StateError('offline'));
        harness.async.flushMicrotasks();
        harness.elapse(const Duration(seconds: 29));
        expect(harness.calls, hasLength(1));
        harness.elapse(const Duration(seconds: 1));
        expect(harness.calls, hasLength(2));
        harness.finish(1, succeeded: false);
        harness.elapse(const Duration(days: 1));
        expect(harness.calls, hasLength(2));
      });
    },
  );

  test('new lifecycle opportunity respects accumulated failure backoff', () {
    run((harness) {
      harness.activate();
      harness.elapse(_debounce);
      harness.finish(0, succeeded: false);
      harness.elapse(const Duration(seconds: 30));
      harness.finish(1, succeeded: false);
      harness.background();
      harness.activate();
      harness.elapse(const Duration(seconds: 59));
      expect(harness.calls, hasLength(2));
      harness.elapse(const Duration(seconds: 1));
      expect(harness.calls, hasLength(3));
    });
  });

  test(
    'ordinary complete evidence suppresses a deferred failed probe retry',
    () {
      run((harness) {
        harness.activate();
        harness.elapse(_debounce);
        harness.finish(0, succeeded: false);
        harness.sample(1);
        harness.elapse(const Duration(minutes: 1));
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test(
    'background cancels waiting work and retains same-owner calibration need',
    () {
      run((harness) {
        harness.activate();
        harness.sample(1);
        harness.calibrate(2);
        harness.background();
        harness.elapse(const Duration(minutes: 1));
        expect(harness.calls, isEmpty);
        harness.activate();
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test(
    'background cancels a flight and its late completion cannot clear new work',
    () {
      run((harness) {
        harness.activate();
        harness.elapse(_debounce);
        harness.background();
        expect(harness.calls[0].cancellation.isCancelled, isTrue);
        harness.activate();
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(2));
        harness.finish(0, succeeded: false);
        expect(harness.coordinator.isProbing, isTrue);
        harness.finish(1, succeeded: true, sampleSequence: 2);
        harness.elapse(const Duration(minutes: 10));
        expect(harness.calls, hasLength(2));
      });
    },
  );

  for (final nextOwner in const <MessageAttentionOwner>[
    (sessionOwner: (uid: '84', revision: 1), sourceGeneration: 3),
    (sessionOwner: (uid: '42', revision: 2), sourceGeneration: 3),
    (sessionOwner: (uid: '42', revision: 1), sourceGeneration: 4),
  ]) {
    test('owner transition isolates evidence and calibration: $nextOwner', () {
      run((harness) {
        harness.activate();
        harness.calibrate(100);
        harness.elapse(_debounce);
        harness.activate(nextOwner);
        expect(harness.calls[0].cancellation.isCancelled, isTrue);
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(2));
        harness.sample(101);
        harness.coordinator.requestCalibration(
          owner: _owner,
          minimumSequence: 102,
        );
        harness.finish(0, succeeded: true);
        expect(harness.coordinator.isProbing, isTrue);
        harness.finish(1, succeeded: true, sampleSequence: 1);
        harness.elapse(const Duration(minutes: 10));
        expect(harness.calls, hasLength(2));
      });
    });
  }

  test(
    'logout retires a flight and does not transfer old calibration to login',
    () {
      run((harness) {
        harness.activate();
        harness.calibrate(100);
        harness.elapse(_debounce);
        harness.coordinator.setEligibility(owner: null, foreground: true);
        expect(harness.calls.single.cancellation.isCancelled, isTrue);
        harness.finish(0, succeeded: false);
        harness.elapse(const Duration(minutes: 1));
        expect(harness.calls, hasLength(1));
        harness.activate();
        harness.sample(1);
        harness.elapse(_debounce);
        expect(harness.calls, hasLength(1));
      });
    },
  );

  test(
    'opt-in interval honors normal fresh samples and stops in background',
    () {
      run(
        (harness) {
          harness.activate();
          harness.sample(1);
          harness.elapse(const Duration(minutes: 2));
          harness.sample(2);
          harness.elapse(const Duration(minutes: 2));
          expect(harness.calls, isEmpty);
          harness.elapse(const Duration(minutes: 1));
          expect(harness.calls, hasLength(1));
          harness.finish(0, succeeded: true, sampleSequence: 3);
          harness.background();
          harness.elapse(const Duration(hours: 1));
          expect(harness.calls, hasLength(1));
        },
        policy: const MessageAttentionProbePolicy(
          foregroundInterval: Duration(minutes: 3),
        ),
      );
    },
  );

  test('opt-in failed interval does not spin on an old fresh timestamp', () {
    run(
      (harness) {
        harness.activate();
        harness.sample(1);
        harness.elapse(const Duration(minutes: 3));
        harness.finish(0, succeeded: false);
        harness.elapse(const Duration(seconds: 30));
        harness.finish(1, succeeded: false);
        harness.elapse(const Duration(seconds: 179));
        expect(harness.calls, hasLength(2));
        harness.elapse(const Duration(seconds: 1));
        expect(harness.calls, hasLength(3));
      },
      policy: const MessageAttentionProbePolicy(
        foregroundInterval: Duration(minutes: 3),
      ),
    );
  });

  test('dispose releases timers and flights and all later input is inert', () {
    run((harness) {
      harness.activate();
      harness.elapse(_debounce);
      harness.coordinator.dispose();
      expect(harness.calls.single.cancellation.isCancelled, isTrue);
      harness.finish(0, succeeded: false);
      harness.activate();
      harness.sample(1);
      harness.calibrate(2);
      harness.elapse(const Duration(days: 1));
      expect(harness.calls, hasLength(1));
    });
  });
}

final class _Harness {
  _Harness(this.async, MessageAttentionProbePolicy policy) {
    coordinator = MessageAttentionProbeCoordinator(
      policy: policy,
      now: () => DateTime.utc(2026, 10, 11).add(async.elapsed),
      probe: (owner, cancellation) {
        final call = _ProbeCall(owner, cancellation);
        calls.add(call);
        return call.completion.future;
      },
    );
  }

  final FakeAsync async;
  late final MessageAttentionProbeCoordinator coordinator;
  final List<_ProbeCall> calls = [];
  MessageAttentionOwner activeOwner = _owner;

  void activate([MessageAttentionOwner owner = _owner]) {
    activeOwner = owner;
    coordinator.setEligibility(owner: owner, foreground: true);
  }

  void background() =>
      coordinator.setEligibility(owner: activeOwner, foreground: false);

  void sample(int sequence) =>
      coordinator.recordFreshSample(owner: _owner, sequence: sequence);

  void calibrate(int sequence) => coordinator.requestCalibration(
    owner: activeOwner,
    minimumSequence: sequence,
  );

  void elapse(Duration duration) => async.elapse(duration);

  void finish(int index, {required bool succeeded, int? sampleSequence}) {
    final call = calls[index];
    if (sampleSequence != null) {
      coordinator.recordFreshSample(
        owner: call.owner,
        sequence: sampleSequence,
      );
    }
    call.completion.complete(succeeded);
    async.flushMicrotasks();
  }
}

final class _ProbeCall {
  _ProbeCall(this.owner, this.cancellation);

  final MessageAttentionOwner owner;
  final ForumRequestCancellation cancellation;
  final Completer<bool> completion = Completer<bool>();
}
