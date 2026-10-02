import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';

void main() {
  late List<_Read> reads;
  late MessageFeedController<int> controller;
  setUp(() {
    reads = [];
    controller = MessageFeedController<int>(
      initialPage: 1,
      load: (page, cancellation) {
        final read = _Read(page, cancellation);
        reads.add(read);
        return read.result.future;
      },
      nextPage: (data) => data < 3 ? data + 1 : null,
      mergeMore: (_, next) => next,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'does not load until activated and coalesces duplicate refreshes',
    () async {
      expect(reads, isEmpty);
      controller.setActive(true);
      final first = controller.refresh();
      expect(controller.refresh(), same(first));
      expect(reads, hasLength(1));
      expect(controller.value.isInitialLoading, isTrue);
      reads.single.succeed(1);
      await first;
      expect(controller.value.data, 1);
      expect(controller.value.isBusy, isFalse);
    },
  );

  test('load-more is single-flight and stops at the last page', () async {
    final first = controller.refresh();
    reads.last.succeed(1);
    await first;
    final second = controller.loadMore();
    expect(controller.loadMore(), same(second));
    expect(reads.last.page, 2);
    expect(controller.value.data, 1);
    reads.last.succeed(2);
    await second;
    final third = controller.loadMore();
    reads.last.succeed(3);
    await third;
    await controller.loadMore();
    expect(reads, hasLength(3));
    expect(controller.hasMore, isFalse);
  });

  test('refresh supersedes pagination and rejects its late result', () async {
    final first = controller.refresh();
    reads.last.succeed(1);
    await first;
    final more = controller.loadMore();
    final old = reads.last;
    final refresh = controller.refresh();
    expect(old.cancellation.isCancelled, isTrue);
    reads.last.succeed(1);
    await refresh;
    old.succeed(2);
    await more;
    expect(controller.value.data, 1);
  });

  test('failed pagination keeps content and can retry the same page', () async {
    final first = controller.refresh();
    reads.last.succeed(1);
    await first;
    final more = controller.loadMore();
    reads.last.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.timeout,
        code: 'timeout',
        diagnosticMessage: 'timeout',
      ),
    );
    await more;
    expect(controller.value.data, 1);
    expect(controller.value.failure?.kind, DataReadFailureKind.timeout);
    final retry = controller.loadMore();
    expect(reads.last.page, 2);
    reads.last.succeed(2);
    await retry;
    expect(controller.value.failure, isNull);
  });

  test(
    'exceptions become safe errors and release the pending operation',
    () async {
      final pending = controller.refresh();
      reads.last.result.completeError(StateError('private payload'));
      await pending;
      expect(
        controller.value.failure?.diagnosticMessage,
        'message_read_failed',
      );
      final retry = controller.refresh();
      reads.last.succeed(1);
      await retry;
      expect(controller.value.data, 1);
    },
  );

  test('session expiry clears previously displayed private data', () async {
    final first = controller.refresh();
    reads.last.succeed(1);
    await first;
    final refresh = controller.refresh();
    reads.last.result.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'login_required',
        diagnosticMessage: 'login_required',
      ),
    );
    await refresh;
    expect(controller.value.data, isNull);
    expect(controller.value.failure?.kind, DataReadFailureKind.unauthorized);
  });

  test('hidden feeds defer invalidation until revisited', () async {
    controller.setActive(true);
    final pending = controller.refresh();
    reads.last.succeed(1);
    await pending;
    controller.setActive(false);
    controller.invalidate();
    controller.invalidate();
    expect(reads, hasLength(1));
    controller.setActive(true);
    expect(reads, hasLength(2));
    reads.last.succeed(1);
    await controller.refresh();
  });

  test('events arriving during a read coalesce without being lost', () async {
    controller.setActive(true);
    final first = controller.refresh();
    controller.invalidate();
    controller.invalidate();
    reads.last.succeed(1);
    await first;
    expect(reads, hasLength(2));
    final second = controller.refresh();
    reads.last.succeed(2);
    await second;
    expect(reads, hasLength(2));
    expect(controller.value.data, 2);
  });

  test('inactive completion does not start a queued refresh', () async {
    controller.setActive(true);
    final first = controller.refresh();
    controller.invalidate();
    controller.setActive(false);
    reads.last.succeed(1);
    await first;
    expect(reads, hasLength(1));
    controller.setActive(true);
    expect(reads, hasLength(2));
    reads.last.succeed(1);
    await controller.refresh();
  });

  test('disposing cancels reads and prevents late listener updates', () async {
    var updates = 0;
    controller.addListener(() => updates++);
    final pending = controller.refresh();
    controller.dispose();
    expect(reads.last.cancellation.isCancelled, isTrue);
    final before = updates;
    reads.last.succeed(1);
    await pending;
    expect(updates, before);
    // Supply a fresh object for tearDown; the disposed instance was checked.
    controller = MessageFeedController(
      initialPage: 1,
      load: (_, _) async => _success(1),
      nextPage: (_) => null,
      mergeMore: (_, next) => next,
    );
  });
}

final class _Read {
  _Read(this.page, this.cancellation);
  final int page;
  final ForumRequestCancellation cancellation;
  final result = Completer<DataReadResult<int, Object?>>();
  void succeed(int value) => result.complete(_success(value));
}

DataReadResult<int, Object?> _success(int value) => DataReadSuccess(
  data: value,
  capabilities: null,
  metadata: const DataReadMetadata.network(),
);
