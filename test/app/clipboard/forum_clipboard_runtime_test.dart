import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_runtime.dart';
import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://bbs.yamibo.com/thread-123-1-1.html';
  const other = 'https://bbs.yamibo.com/thread-124-1-1.html';

  group('ForumClipboardRuntime', () {
    test(
      'the cold check waits for UI availability and survives shell changes',
      () async {
        final fixture = _Fixture();
        final firstHost = fixture.runtime.attach();
        fixture.runtime.requestColdCheck(firstHost);
        fixture.runtime.requestColdCheck(firstHost);
        expect(fixture.runtime.needsColdCheck, isFalse);
        expect(fixture.reads, isEmpty);

        fixture.runtime.updateEligibility(firstHost, available: true);
        expect(fixture.reads, hasLength(1));
        await fixture.complete(0, url);
        final candidate = fixture.runtime.coordinator.candidate!;
        fixture.runtime.coordinator.markShown(candidate);
        fixture.runtime.coordinator.dismiss(candidate);
        fixture.runtime.detach(firstHost);

        final secondHost = fixture.runtime.attach();
        fixture.runtime.updateEligibility(secondHost, available: true);
        fixture.runtime.requestColdCheck(secondHost);
        await _flush();
        expect(fixture.reads, hasLength(1));
        fixture.runtime.coordinator.requestCheck();
        await fixture.complete(1, url);
        expect(fixture.runtime.coordinator.candidate, isNull);
      },
    );

    for (final gate in ['WAF', 'update']) {
      test('$gate defers the cold check until the host is available', () async {
        final fixture = _Fixture();
        final host = fixture.runtime.attach();
        fixture.gate(gate, true);
        fixture.runtime.updateEligibility(host, available: true);
        fixture.runtime.requestColdCheck(host);
        expect(fixture.runtime.isUnblocked, isFalse);
        expect(fixture.reads, isEmpty);

        fixture.gate(gate, false);
        expect(fixture.runtime.isUnblocked, isTrue);
        expect(fixture.reads, isEmpty);
        fixture.runtime.updateEligibility(host, available: true);
        await fixture.complete(0, url);
        expect(fixture.runtime.coordinator.candidate?.url, url);
        fixture.runtime.updateEligibility(host, available: true);
        expect(fixture.reads, hasLength(1));
      });

      test(
        '$gate rejects late reads and preserves one pending opportunity',
        () async {
          final fixture = _Fixture();
          final host = fixture.runtime.attach();
          fixture.runtime.updateEligibility(host, available: true);
          fixture.runtime.requestColdCheck(host);
          fixture.gate(gate, true);
          fixture.runtime.coordinator.requestCheck();
          fixture.runtime.coordinator.requestCheck();
          await fixture.complete(0, url);
          expect(fixture.runtime.coordinator.candidate, isNull);
          expect(fixture.reads, hasLength(1));

          fixture.gate(gate, false);
          fixture.runtime.updateEligibility(host, available: true);
          await fixture.complete(1, other);
          expect(fixture.runtime.coordinator.candidate?.url, other);
          expect(fixture.maxActiveReads, 1);
        },
      );

      test(
        '$gate preserves a confirmed open until its owner changes',
        () async {
          final fixture = _Fixture();
          final host = fixture.runtime.attach();
          fixture.runtime.updateEligibility(host, available: true);
          fixture.runtime.requestColdCheck(host);
          await fixture.complete(0, url);
          final lease = fixture.runtime.coordinator.takeForOpen(
            fixture.runtime.coordinator.candidate!,
          )!;
          fixture.gate(gate, true);
          expect(lease(), isTrue);
          fixture.runtime.updateEligibility(host, available: true);
          expect(lease(), isTrue);
          fixture.runtime.changeOwner();
          expect(lease(), isFalse);
          fixture.gate(gate, false);
          fixture.runtime.updateEligibility(host, available: true);
          expect(fixture.reads, hasLength(1));
        },
      );
    }

    test(
      'replacement hosts isolate stale lifecycle calls and pending reads',
      () async {
        final fixture = _Fixture();
        final oldHost = fixture.runtime.attach();
        fixture.runtime.updateEligibility(oldHost, available: true);
        fixture.runtime.requestColdCheck(oldHost);
        final currentHost = fixture.runtime.attach();
        fixture.runtime.updateEligibility(currentHost, available: true);
        expect(fixture.runtime.owns(oldHost), isFalse);
        expect(fixture.runtime.owns(currentHost), isTrue);

        fixture.runtime.detach(oldHost);
        fixture.runtime.updateEligibility(oldHost, available: false);
        fixture.runtime.requestColdCheck(oldHost);
        await fixture.complete(0, url);
        expect(fixture.runtime.coordinator.candidate, isNull);
        expect(fixture.reads, hasLength(2));
        await fixture.complete(1, other);
        expect(fixture.runtime.coordinator.candidate?.url, other);
        expect(fixture.maxActiveReads, 1);
        final lease = fixture.runtime.coordinator.takeForOpen(
          fixture.runtime.coordinator.candidate!,
        )!;
        fixture.runtime.detach(oldHost);
        expect(lease(), isTrue);
        fixture.runtime.detach(currentHost);
        expect(lease(), isFalse);
      },
    );

    test(
      'owner replacement rejects late results before the new host rechecks',
      () async {
        final fixture = _Fixture();
        final host = fixture.runtime.attach();
        fixture.runtime.updateEligibility(host, available: true);
        fixture.runtime.requestColdCheck(host);
        fixture.runtime.changeOwner();
        await fixture.complete(0, url);
        expect(fixture.runtime.coordinator.candidate, isNull);
        expect(fixture.reads, hasLength(1));

        fixture.runtime.updateEligibility(host, available: true);
        await fixture.complete(1, other);
        expect(fixture.runtime.coordinator.candidate?.url, other);
        expect(fixture.maxActiveReads, 1);
      },
    );

    test('dispose retires queued reads and all existing host tokens', () async {
      final fixture = _Fixture();
      final host = fixture.runtime.attach();
      fixture.runtime.updateEligibility(host, available: true);
      fixture.runtime.requestColdCheck(host);
      fixture.runtime.coordinator.requestCheck();
      fixture.runtime.dispose();
      fixture.disposed = true;
      expect(fixture.runtime.owns(host), isFalse);
      fixture.runtime.updateEligibility(host, available: true);
      fixture.runtime.requestColdCheck(host);
      fixture.runtime.detach(host);
      fixture.runtime.changeOwner();
      await fixture.complete(0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reads, hasLength(1));
      expect(fixture.runtime.coordinator.isReading, isFalse);
    });
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  _Fixture() {
    runtime = ForumClipboardRuntime(
      readText: () {
        final read = Completer<String?>();
        reads.add(read);
        activeReads++;
        if (activeReads > maxActiveReads) maxActiveReads = activeReads;
        return read.future.whenComplete(() => activeReads--);
      },
      selfCopyRegistry: SelfCopyFingerprintRegistry(),
    );
    addTearDown(() {
      if (!disposed) runtime.dispose();
    });
  }

  late final ForumClipboardRuntime runtime;
  final reads = <Completer<String?>>[];
  var activeReads = 0;
  var maxActiveReads = 0;
  var disposed = false;

  void gate(String gate, bool blocked) {
    if (gate == 'WAF') {
      runtime.setWafBusy(blocked);
    } else {
      runtime.setUpdateBlocked(blocked);
    }
  }

  Future<void> complete(int index, String? text) async {
    reads[index].complete(text);
    await _flush();
  }
}
