import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

import '../test_support/native_reader_test_fixture.dart';

Future<void> _until(bool Function() ready) async {
  for (var step = 0; step < 10000; step++) {
    if (ready()) return;
    await Future<void>.value();
  }
  fail('Native anchor navigation did not settle');
}

NovelReaderTextAnchor _anchor(
  NativeReaderTestFixture fixture,
  int offset, {
  int segment = 0,
}) => fixture.anchors.segments[segment].projection.baseAnchor.copyWith(
  textOffset: offset,
);

NovelReaderNativePagedController _controller(
  NativeReaderTestFixture fixture, {
  NovelReaderNativeWorkScheduler? scheduler,
  Future<void> Function()? idle,
  NovelReaderPaginationPerformancePolicy performance =
      const NovelReaderPaginationPerformancePolicy(enforceBudgets: false),
}) {
  final anchor = _anchor(fixture, 0);
  final controller = NovelReaderNativePagedController(
    session: fixture.session,
    anchors: fixture.anchors,
    position: NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: 'episode',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorNodeId: anchor.nodeId,
      anchorTextOffset: 0,
      anchorFormatVersion: anchor.formatVersion,
      anchorTextIdentity: anchor.textIdentity,
      progressPercent: 0,
      isProgressPercentValid: true,
    ),
    paginationKey: 'geometry',
    parent: fixture.parent,
    scheduler:
        scheduler ?? NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    idleScheduler: idle ?? () async {},
    performance: performance,
  );
  addTearDown(controller.close);
  return controller;
}

Future<
  ({
    NovelReaderPaginationPosition position,
    List<ForumBodyParagraphLease> leases,
  })
>
_confirm(NovelReaderNativePagedController controller) async {
  await _until(
    () =>
        controller.readyTarget != null ||
        controller.error != null && !controller.hasPendingNavigation,
  );
  expect(controller.readyTarget, isNotNull);
  final target = controller.readyTarget!;
  final leases = target.view.takeLeases();
  addTearDown(() {
    for (final lease in leases) {
      lease.release();
    }
  });
  return (position: controller.confirmVisible(target, leases)!, leases: leases);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('anchor expiry retires work and timers while preserving mounted end-user resources', () {
    fakeAsync((clock) {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
      );
      var held = false;
      final gate = Completer<void>();
      final controller = _controller(
        fixture,
        scheduler: NovelReaderNativeWorkScheduler(
          nextFrame: () async {
            if (held) await gate.future;
          },
        ),
        performance: const NovelReaderPaginationPerformancePolicy(
          targetPageWait: Duration(milliseconds: 100),
        ),
      );
      controller.start();
      clock.flushMicrotasks();
      final initial = controller.readyTarget!;
      final leases = initial.view.takeLeases();
      controller.confirmVisible(initial, leases);
      held = true;
      expect(controller.requestAnchor(_anchor(fixture, 5)), isTrue);
      clock.elapse(const Duration(milliseconds: 100));
      expect(controller.phase, NovelReaderNativePagedPhase.paused);
      expect(controller.hasPendingNavigation, isFalse);
      expect(controller.readyTarget, isNull);
      expect(controller.visiblePageIndex, 0);
      expect(leases.single.isActive, isTrue);
      expect(fixture.session.reservedViewLeases, 0);
      expect(clock.nonPeriodicTimerCount, 0);
      held = false;
      gate.complete();
      clock.flushMicrotasks();
      expect(controller.readyTarget, isNull);
      expect(controller.requestAnchor(_anchor(fixture, 1)), isTrue);
      clock.flushMicrotasks();
      final recovered = controller.readyTarget!;
      final recoveredLeases = recovered.view.takeLeases();
      expect(
        controller
            .confirmVisible(recovered, recoveredLeases)!
            .anchor
            .textOffset,
        1,
      );
      expect(clock.nonPeriodicTimerCount, 0);
      controller.close();
      leases.single.release();
      recoveredLeases.single.release();
      clock.flushMicrotasks();
      expect(fixture.session.isClosed, isFalse);
      expect(fixture.parent.isCancelled, isFalse);
    });
  });

  test('replacing and cancelling paused-prefix anchor work releases its probe and rejects late frames', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p><blockquote>unsupported</blockquote>',
      width: 20,
      height: 10,
      complete: false,
    );
    var held = false;
    final gate = Completer<void>();
    final controller = _controller(
      fixture,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) await gate.future;
        },
      ),
    );
    controller.start();
    final initial = await _confirm(controller);
    await _until(() => controller.error != null);
    final error = controller.error;
    final prefix = controller.snapshot;
    held = true;
    expect(controller.requestAnchor(_anchor(fixture, 5)), isTrue);
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }
    expect(controller.requestAnchor(_anchor(fixture, 3)), isTrue);
    expect(controller.cancelPendingNavigation(), isTrue);
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }
    expect(fixture.session.pendingPreparationCount, 0);
    expect(fixture.session.reservedViewLeases, 0);
    held = false;
    gate.complete();
    for (var i = 0; i < 50; i++) {
      await Future<void>.value();
    }
    expect(controller.error, same(error));
    expect(controller.snapshot, same(prefix));
    expect(controller.readyTarget, isNull);
    expect(controller.hasPendingNavigation, isFalse);
    expect(initial.leases.single.isActive, isTrue);
    expect(controller.requestPage(1), isTrue);
    expect((await _confirm(controller)).position.pageIndex, 1);
  });

  test('exact anchor resolves in a partial prefix with the same source and native layout', () async {
    final fixture = NativeReaderTestFixture(
      '<p>${'abcdefghij' * 6}</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final idle = Completer<void>();
    addTearDown(() {
      if (!idle.isCompleted) idle.complete();
    });
    var idleCalls = 0;
    final controller = _controller(
      fixture,
      idle: () {
        idleCalls++;
        return idle.future;
      },
    );
    controller.start();
    final original = await _confirm(controller);
    await _until(() => idleCalls > 0);
    final prefix = controller.snapshot!;
    expect(prefix.isComplete, isFalse);
    expect(controller.requestAnchor(_anchor(fixture, 5)), isTrue);
    await _until(() => controller.readyTarget != null);
    expect(controller.visiblePageIndex, 0);
    expect(controller.snapshot!.isComplete, isFalse);
    expect(controller.snapshot![0], same(prefix[0]));
    final target = await _confirm(controller);
    expect(target.position.pageIndex, 2);
    expect(target.position.anchor.textOffset, 5);
    expect(target.position.hasUserNavigated, isTrue);
    expect(target.position.isReadOnlyCompatibilityRestore, isFalse);
    expect(original.leases.every((lease) => lease.isActive), isTrue);
    expect(fixture.cache.layoutBuildCount, 1);
  });

  for (final version in [0, 1, 37]) {
    test(
      'explicit recorded-node compatibility version $version selects the target node on a mixed-node page',
      () async {
        final fixture = NativeReaderTestFixture(
          '<p>ab</p><p>cd</p>',
          width: 100,
          height: 30,
        );
        final controller = _controller(fixture);
        controller.start();
        final original = await _confirm(controller);
        final canonical = _anchor(
          fixture,
          0,
          segment: fixture.anchors.segments.length - 1,
        );
        expect(canonical.nodeId, isNot(original.position.anchor.nodeId));
        final old = canonical.copyWith(
          textOffset: 777,
          formatVersion: version,
          textIdentity: version == 1
              ? 'different text'
              : canonical.textIdentity,
        );
        expect(controller.requestAnchor(old), isTrue);
        final target = await _confirm(controller);
        expect(target.position.anchor.nodeId, canonical.nodeId);
        expect(target.position.anchor.textOffset, 0);
        expect(target.position.anchor.textIdentity, canonical.textIdentity);
        expect(target.position.anchor.formatVersion, 1);
        expect(target.position.hasUserNavigated, isTrue);
        expect(target.position.isReadOnlyCompatibilityRestore, isFalse);
        expect(old.formatVersion, version);
        expect(controller.error, isNull);
      },
    );
  }

  for (final html in [
    '<p>a\u0301b</p>',
    '<p>a<span style="visibility:hidden">bcd</span>e</p>',
  ]) {
    test(
      'uncovered canonical offset in $html cannot fall back to node or percentage',
      () async {
        final fixture = NativeReaderTestFixture(html, width: 100, height: 10);
        final controller = _controller(fixture);
        controller.start();
        final original = await _confirm(controller);
        final anchor = _anchor(fixture, html.contains('hidden') ? 2 : 1);
        expect(fixture.anchors.sourceCandidates(anchor), isNotEmpty);
        expect(controller.requestAnchor(anchor), isTrue);
        final revision = controller.navigationRevision;
        await _until(
          () =>
              controller.unavailableAnchorRevision == revision ||
              controller.error != null,
        );
        expect(controller.error, isNull);
        expect(controller.unavailableAnchorRevision, revision);
        expect(controller.readyTarget, isNull);
        expect(controller.hasPendingNavigation, isFalse);
        expect(controller.visiblePageIndex, original.position.pageIndex);
        expect(original.leases.every((lease) => lease.isActive), isTrue);
        expect(controller.requestAnchor(_anchor(fixture, 0)), isTrue);
        expect((await _confirm(controller)).position.hasUserNavigated, isTrue);
      },
    );
  }

  test('clipped canonical glyph has no explicit-navigation coverage', () async {
    final fixture = NativeReaderTestFixture('<p>a</p>', width: 1, height: 10);
    final controller = _controller(fixture);
    controller.start();
    await _confirm(controller);
    expect(controller.requestAnchor(_anchor(fixture, 0)), isTrue);
    await _until(
      () =>
          controller.unavailableAnchorRevision == controller.navigationRevision,
    );
    expect(controller.readyTarget, isNull);
    expect(controller.hasPendingNavigation, isFalse);
    expect(controller.error, isNull);
  });

  test('failed source searches only accepted prefix and preserves its original failure on hit and miss', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p><blockquote>unsupported</blockquote><p>outside</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final controller = _controller(fixture);
    controller.start();
    final original = await _confirm(controller);
    await _until(() => controller.error != null);
    final error = controller.error;
    final prefix = controller.snapshot;
    expect(controller.requestAnchor(_anchor(fixture, 5)), isTrue);
    final hit = await _confirm(controller);
    expect(hit.position.anchor.textOffset, 5);
    expect(hit.position.hasUserNavigated, isTrue);
    expect(controller.error, same(error));
    expect(controller.snapshot, same(prefix));
    final outside = _anchor(
      fixture,
      1,
      segment: fixture.anchors.segments.length - 1,
    );
    expect(controller.requestAnchor(outside), isTrue);
    final revision = controller.navigationRevision;
    await _until(() => controller.unavailableAnchorRevision == revision);
    expect(controller.error, same(error));
    expect(controller.snapshot, same(prefix));
    expect(controller.readyTarget, isNull);
    expect(controller.hasPendingNavigation, isFalse);
    expect(controller.visiblePageIndex, hit.position.pageIndex);
    expect(original.leases.every((lease) => lease.isActive), isTrue);
    expect(controller.requestPage(1), isTrue);
    expect((await _confirm(controller)).position.pageIndex, 1);
  });

  for (final action in ['page', 'cancel', 'hide', 'invalid']) {
    test(
      '$action retires an anchor request before first paint and ignores its late frame',
      () async {
        final fixture = NativeReaderTestFixture(
          '<p>abcdefgh</p>',
          width: 20,
          height: 10,
        );
        final gate = Completer<void>();
        var held = true;
        final controller = _controller(
          fixture,
          scheduler: NovelReaderNativeWorkScheduler(
            nextFrame: () async {
              if (held) await gate.future;
            },
          ),
        );
        controller.start();
        expect(controller.requestAnchor(_anchor(fixture, 5)), isTrue);
        switch (action) {
          case 'page':
            expect(controller.requestPage(3), isTrue);
          case 'cancel':
            expect(controller.cancelPendingNavigation(), isTrue);
          case 'hide':
            expect(controller.suspend(), isTrue);
          case 'invalid':
            expect(
              controller.requestAnchor(
                _anchor(fixture, 0).copyWith(episodeId: 'other'),
              ),
              isFalse,
            );
        }
        held = false;
        gate.complete();
        if (action == 'hide') controller.resume();
        final actual = await _confirm(controller);
        expect(actual.position.pageIndex, action == 'page' ? 3 : 0);
        expect(actual.position.hasUserNavigated, action == 'page');
        expect(controller.error, isNull);
      },
    );
  }

  test('unavailable target before first paint returns to the original canonical bootstrap without user navigation', () async {
    final fixture = NativeReaderTestFixture(
      '<p>a\u0301b</p>',
      width: 100,
      height: 10,
    );
    final gate = Completer<void>();
    var held = true;
    final controller = _controller(
      fixture,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) await gate.future;
        },
      ),
    );
    controller.start();
    expect(controller.requestAnchor(_anchor(fixture, 1)), isTrue);
    final revision = controller.navigationRevision;
    held = false;
    gate.complete();
    final actual = await _confirm(controller);
    expect(controller.unavailableAnchorRevision, revision);
    expect(actual.position.anchor.textOffset, 0);
    expect(actual.position.hasUserNavigated, isFalse);
    expect(controller.error, isNull);
  });
}
