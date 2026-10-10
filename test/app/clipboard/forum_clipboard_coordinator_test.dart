import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_coordinator.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_policy.dart';
import 'package:y300/core/clipboard/self_copy_fingerprint_registry.dart';

void main() {
  const url = 'https://bbs.yamibo.com/thread-123-1-1.html';
  const other = 'https://bbs.yamibo.com/thread-124-1-1.html';

  group('ForumClipboardCoordinator', () {
    test(
      'one deferred cold intent runs once when the host becomes eligible',
      () async {
        final fixture = _Fixture();
        fixture.eligibility(available: false);
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        expect(fixture.reads, isEmpty);
        fixture.eligibility();
        expect(fixture.reads, hasLength(1));
        await fixture.complete(0, url);
        expect(fixture.coordinator.candidate?.url, url);
        fixture.eligibility();
        await _flush();
        expect(fixture.reads, hasLength(1));
      },
    );

    test(
      'availability or ordinary rebuilds do not create a read opportunity',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.eligibility(available: false);
        fixture.eligibility();
        await _flush();
        expect(fixture.reads, isEmpty);
        fixture.coordinator.requestCheck();
        await fixture.complete(0, null);
        fixture.eligibility();
        expect(fixture.reads, hasLength(1));
      },
    );

    test(
      'new opportunities merge behind a single in-flight platform read',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        expect(fixture.reads, hasLength(1));
        await fixture.complete(0, url);
        expect(fixture.changes, isEmpty);
        expect(fixture.reads, hasLength(2));
        await fixture.complete(1, other);
        expect(fixture.coordinator.candidate?.url, other);
        expect(fixture.maxActiveReads, 1);
        expect(fixture.coordinator.isReading, isFalse);
      },
    );

    test(
      'a lost host drops late reads and resumes only its pending intent',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.eligibility(available: false);
        await fixture.complete(0, url);
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.reads, hasLength(1));
        fixture.eligibility();
        expect(fixture.reads, hasLength(2));
        await fixture.complete(1, other);
        expect(fixture.coordinator.candidate?.url, other);
      },
    );

    test(
      'an unshown stale candidate is reread rather than reused on return',
      () async {
        final fixture = _Fixture();
        final first = await fixture.show(url);
        fixture.eligibility(available: false);
        expect(fixture.coordinator.candidate, isNull);
        fixture.coordinator.markShown(first);
        fixture.eligibility();
        await fixture.complete(1, other);
        expect(fixture.coordinator.candidate?.url, other);
        expect(fixture.changes.map((candidate) => candidate?.url), [
          url,
          null,
          other,
        ]);
      },
    );

    test(
      'owner changes retire old work and let a fresh owner read progress',
      () async {
        final fixture = _Fixture();
        fixture.eligibility(owner: 'old');
        fixture.coordinator.requestCheck();
        fixture.eligibility(owner: 'new');
        expect(fixture.reads, hasLength(1));
        await fixture.complete(0, url);
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.reads, hasLength(2));
        await fixture.complete(1, other);
        expect(fixture.coordinator.candidate?.url, other);
        expect(fixture.maxActiveReads, 1);
      },
    );

    test(
      'suspension rejects late reads and coalesces blocked lifecycle checks',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.eligibility(available: false);
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        await fixture.complete(0, url);
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.reads, hasLength(1));
        fixture.eligibility();
        expect(fixture.reads, hasLength(2));
        await fixture.complete(1, other);
        expect(fixture.coordinator.candidate?.url, other);
        expect(fixture.maxActiveReads, 1);
      },
    );

    test(
      'a read failure or absent/nonmatching text ends quietly without retry',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.reads[0].completeError(StateError('synthetic platform error'));
        await _flush();
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.coordinator.isReading, isFalse);
        expect(fixture.reads, hasLength(1));
        for (final text in [
          null,
          '',
          'ordinary text',
          'https://example.com/',
        ]) {
          fixture.coordinator.requestCheck();
          await fixture.complete(fixture.reads.length - 1, text);
          expect(fixture.coordinator.candidate, isNull);
        }
        expect(fixture.changes, isEmpty);
      },
    );

    test(
      'a failed old read yields its slot to one explicit pending intent',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        fixture.reads[0].completeError(StateError('synthetic platform error'));
        await _flush();
        expect(fixture.reads, hasLength(2));
        expect(fixture.coordinator.candidate, isNull);
        await fixture.complete(1, url);
        expect(fixture.coordinator.candidate?.url, url);
        expect(fixture.maxActiveReads, 1);
      },
    );

    test(
      'known successful self copies are suppressed without retaining text',
      () async {
        final fixture = _Fixture();
        const copied = '分享：$url';
        fixture.registry.recordSuccessfulWrite(copied);
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        await fixture.complete(0, copied);
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.registry.length, 1);
        fixture.coordinator.requestCheck();
        await fixture.complete(1, url);
        expect(fixture.coordinator.candidate?.url, url);
      },
    );

    test(
      'only an actual shown candidate records target deduplication',
      () async {
        final fixture = _Fixture();
        final first = await fixture.show(url);
        fixture.eligibility(available: false);
        fixture.coordinator.markShown(first);
        fixture.eligibility();
        await fixture.complete(1, url);
        final second = fixture.coordinator.candidate!;
        fixture.coordinator.markShown(second);
        fixture.coordinator.requestCheck();
        await fixture.complete(2, '说明改变：$url');
        expect(fixture.coordinator.candidate, isNull);
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        await fixture.complete(
          3,
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123',
        );
        expect(fixture.coordinator.candidate, isNull);
      },
    );

    test(
      'dismiss and open mark processed targets and reject stale callbacks',
      () async {
        final fixture = _Fixture();
        final first = await fixture.show(url);
        fixture.coordinator.dismiss(first);
        expect(fixture.coordinator.candidate, isNull);
        expect(fixture.coordinator.takeForOpen(first), isNull);
        fixture.coordinator.requestCheck();
        await fixture.complete(1, url);
        expect(fixture.coordinator.candidate, isNull);
        fixture.coordinator.requestCheck();
        await fixture.complete(2, other);
        final second = fixture.coordinator.candidate!;
        fixture.coordinator.dismiss(first);
        fixture.coordinator.markShown(first);
        expect(fixture.coordinator.candidate, same(second));
        final lease = fixture.coordinator.takeForOpen(second)!;
        expect(lease(), isTrue);
        expect(fixture.coordinator.candidate, isNull);
        fixture.coordinator.requestCheck();
        await fixture.complete(3, other);
        expect(fixture.coordinator.candidate, isNull);
        expect(lease(), isFalse);
      },
    );

    test(
      'route coverage preserves an open lease but real suspension retires it',
      () async {
        final fixture = _Fixture();
        final candidate = await fixture.show(url);
        final lease = fixture.coordinator.takeForOpen(candidate)!;
        fixture.eligibility(available: false);
        expect(lease(), isTrue);
        fixture.coordinator.cancelOperations();
        expect(lease(), isFalse);
        fixture.eligibility();
        expect(fixture.reads, hasLength(1));
      },
    );

    for (final mutation in ['request', 'owner', 'suspend', 'dispose']) {
      test('an open lease is retired by $mutation', () async {
        final fixture = _Fixture();
        final candidate = await fixture.show(url);
        final lease = fixture.coordinator.takeForOpen(candidate)!;
        switch (mutation) {
          case 'request':
            fixture.coordinator.requestCheck();
          case 'owner':
            fixture.eligibility(owner: 'new');
          case 'suspend':
            fixture.eligibility(available: false);
            fixture.coordinator.cancelOperations();
          case 'dispose':
            fixture.coordinator.dispose();
        }
        expect(lease(), isFalse);
        for (final read in fixture.reads.where((read) => !read.isCompleted)) {
          read.complete(null);
        }
        await _flush();
      });
    }

    test(
      'twenty handled fingerprints form an LRU across eligibility rebuilds',
      () async {
        final fixture = _Fixture();
        for (var index = 0; index < 20; index++) {
          final candidate = await fixture.show(_url(index));
          fixture.coordinator.dismiss(candidate);
        }
        fixture.eligibility(available: false);
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        await fixture.complete(20, _url(0));
        expect(fixture.coordinator.candidate, isNull);
        final latest = await fixture.show(_url(20));
        fixture.coordinator.dismiss(latest);
        fixture.coordinator.requestCheck();
        await fixture.complete(22, _url(1));
        expect(fixture.coordinator.candidate?.url, _url(1));
        fixture.coordinator.dismiss(fixture.coordinator.candidate!);
        fixture.coordinator.requestCheck();
        await fixture.complete(23, _url(0));
        expect(fixture.coordinator.candidate, isNull);
      },
    );

    test(
      'disposing a pending read prevents publication and followup reads',
      () async {
        final fixture = _Fixture();
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        fixture.coordinator.requestCheck();
        fixture.coordinator.dispose();
        await fixture.complete(0, url);
        fixture.eligibility();
        fixture.coordinator.requestCheck();
        expect(fixture.changes, isEmpty);
        expect(fixture.reads, hasLength(1));
        expect(fixture.coordinator.candidate, isNull);
      },
    );

    test('history capacity must be positive', () {
      expect(
        () => ForumClipboardCoordinator(
          readText: () async => null,
          selfCopyRegistry: SelfCopyFingerprintRegistry(),
          onChanged: (_) {},
          historyCapacity: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

String _url(int index) =>
    'https://bbs.yamibo.com/thread-${1000 + index}-1-1.html';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  _Fixture() {
    coordinator = ForumClipboardCoordinator(
      readText: () {
        final read = Completer<String?>();
        reads.add(read);
        activeReads++;
        if (activeReads > maxActiveReads) maxActiveReads = activeReads;
        return read.future.whenComplete(() => activeReads--);
      },
      selfCopyRegistry: registry,
      onChanged: changes.add,
    );
    addTearDown(coordinator.dispose);
  }

  late final ForumClipboardCoordinator coordinator;
  final registry = SelfCopyFingerprintRegistry();
  final reads = <Completer<String?>>[];
  final changes = <ForumClipboardLinkCandidate?>[];
  var activeReads = 0;
  var maxActiveReads = 0;

  void eligibility({bool available = true, Object? owner = 'owner'}) =>
      coordinator.updateEligibility(available: available, owner: owner);

  Future<void> complete(int index, String? text) async {
    reads[index].complete(text);
    await _flush();
  }

  Future<ForumClipboardLinkCandidate> show(String text) async {
    eligibility();
    coordinator.requestCheck();
    await complete(reads.length - 1, text);
    return coordinator.candidate!;
  }
}
