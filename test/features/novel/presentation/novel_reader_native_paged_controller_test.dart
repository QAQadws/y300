import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_delivery.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_view_window.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

import '../test_support/native_reader_test_fixture.dart';

Future<void> _until(bool Function() test, {String context = ''}) async {
  for (var step = 0; step < 10000; step++) {
    if (test()) return;
    await Future<void>.value();
  }
  fail('Native controller did not reach the expected state $context');
}

NovelReaderTextAnchor _anchor(NativeReaderTestFixture fixture, int offset) =>
    fixture.anchors.segments.first.projection.baseAnchor.copyWith(
      textOffset: offset,
    );
NovelReaderProgressSnapshot _position(NovelReaderTextAnchor anchor) =>
    NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: 'episode',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 99,
      anchorNodeId: anchor.nodeId,
      anchorTextOffset: anchor.textOffset,
      anchorFormatVersion: anchor.formatVersion,
      anchorTextIdentity: anchor.textIdentity,
      progressPercent: .95,
      isProgressPercentValid: true,
    );

NovelReaderNativePagedController _controller(
  NativeReaderTestFixture fixture, {
  NovelReaderProgressSnapshot? position,
  NovelReaderTextAnchor? conversionAnchor,
  NovelReaderChapterEdge? entry,
  NovelReaderNativeWorkScheduler? scheduler,
  NovelReaderNativeViewWindowLimits windowLimits =
      const NovelReaderNativeViewWindowLimits(radius: 0),
  NovelReaderPaginationPerformancePolicy performance =
      const NovelReaderPaginationPerformancePolicy(enforceBudgets: false),
}) {
  final value = NovelReaderNativePagedController(
    session: fixture.session,
    anchors: fixture.anchors,
    position: position ?? _position(_anchor(fixture, 0)),
    paginationKey: 'geometry',
    parent: fixture.parent,
    entryEdge: entry,
    conversionAnchor: conversionAnchor,
    scheduler:
        scheduler ?? NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    performance: performance,
    idleScheduler: () async {},
    windowLimits: windowLimits,
  );
  addTearDown(value.close);
  return value;
}

Future<
  ({
    NativeReaderTestFixture fixture,
    NovelReaderNativePagedController controller,
    List<ForumBodyParagraphLease> leases,
  })
>
_failedReadable({
  NovelReaderNativeWorkScheduler? scheduler,
  NovelReaderPaginationPerformancePolicy performance =
      const NovelReaderPaginationPerformancePolicy(enforceBudgets: false),
}) async {
  final fixture = NativeReaderTestFixture(
    '<p>abcdefgh</p><p>ij</p><div style="position:absolute">unsupported</div>',
    width: 20,
    height: 10,
    complete: false,
  );
  final controller = _controller(
    fixture,
    entry: NovelReaderChapterEdge.start,
    scheduler: scheduler,
    performance: performance,
  );
  controller.start();
  await _until(
    () => controller.readyTarget != null || controller.error != null,
  );
  final delivery = controller.readyTarget!;
  final leases = delivery.view.takeLeases();
  controller.confirmVisible(delivery, leases);
  await _until(() => controller.error != null);
  return (fixture: fixture, controller: controller, leases: leases);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final format in [1, 37]) {
    test(
      'author language inputs keep actual ruby coverage and restore authority format=$format',
      () async {
        final fixture = NativeReaderTestFixture(
          '<p lang="ja">A<ruby lang="zh-Hant">B<rt lang="ko">x</rt></ruby>'
          '<span lang="">C</span><span lang="ar">D</span></p>',
        );
        final controller = _controller(
          fixture,
          position: _position(_anchor(fixture, 0))
              .copyWith(anchorFormatVersion: format),
        );
        controller.start();
        await _until(
          () => controller.readyTarget != null || controller.error != null,
        );
        expect(controller.error, isNull);
        final delivery = controller.readyTarget!;
        final fragments = delivery.view.takeFragments();
        expect(
          fragments
              .expand((fragment) => fragment.runs)
              .map((run) => run.style.textStyle.locale)
              .toSet(),
          {
            const Locale('ja'),
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
            const Locale('ko'),
            const Locale('und'),
            const Locale('ar'),
          },
        );
        expect(
          fragments
              .expand((fragment) => fragment.runs)
              .every((run) => run.style.textDirection == TextDirection.ltr),
          isTrue,
        );
        addTearDown(() {
          for (final fragment in fragments) {
            fragment.close();
          }
        });
        expect(delivery.view.coverage.hasClippedGlyphs, isFalse);
        final report = controller.confirmPreparedVisible(delivery, fragments)!;
        expect(report.isWholeBodyVisible, isTrue);
        expect(report.isReadOnlyCompatibilityRestore, format != 1);
        expect(report.hasUserNavigated, isFalse);
        expect(controller.visiblePageIndex, 0);
        expect(fixture.session.takePendingIssues(), isEmpty);
      },
    );
  }

  for (final (targetPage, retirement) in [
    (1, ''),
    (2, ''),
    (1, 'suspend'),
    (1, 'close'),
  ]) {
    test(
      'former mounted page release retries a deferred EOF neighbor target=$targetPage retire=$retirement',
      () async {
        const html = '<p>ab</p><p>cd</p><p>ef</p><p>gh</p>';
        final fixture = NativeReaderTestFixture(
          html,
          width: 20,
          height: 10,
          cacheEntries: 2,
        );
        var frames = 0;
        final controller = _controller(
          fixture,
          entry: NovelReaderChapterEdge.start,
          windowLimits: const NovelReaderNativeViewWindowLimits(radius: 1),
          scheduler: NovelReaderNativeWorkScheduler(
            nextFrame: () async {
              frames++;
            },
          ),
        );
        controller.start();
        await _until(() => controller.readyTarget != null);
        final original = controller.readyTarget!;
        final originLeases = original.view.takeLeases();
        addTearDown(() {
          for (final lease in originLeases) {
            lease.release();
          }
        });
        expect(controller.confirmVisible(original, originLeases), isNotNull);
        await _until(() => controller.viewForPage(1) != null);
        expect(controller.requestPage(targetPage), isTrue);
        await _until(() => controller.readyTarget != null);
        final target = controller.readyTarget!;
        final targetLeases = target.view.takeLeases();
        addTearDown(() {
          for (final lease in targetLeases) {
            lease.release();
          }
        });
        expect(controller.confirmVisible(target, targetLeases), isNotNull);
        for (var step = 0; step < 100; step++) {
          await Future<void>.value();
        }
        expect(controller.error, isNull);
        expect(controller.snapshot!.isComplete, isTrue);
        expect(controller.viewForPage(targetPage + 1), isNull);
        expect(fixture.cache.activeLeases, 2);
        expect(fixture.session.pendingPreparationCount, 0);
        final revision = controller.navigationRevision;
        if (targetPage == 2) {
          // Identical source/layout strings do not make another session's page an
          // unmount acknowledgement. The original page is already outside radius.
          final other = NativeReaderTestFixture(html, width: 20, height: 10);
          final obsolete = _controller(
            other,
            entry: NovelReaderChapterEdge.start,
          );
          obsolete.start();
          await _until(() => obsolete.readyTarget != null);
          final stale = obsolete.readyTarget!.view;
          expect(stale.snapshot.identity, controller.snapshot!.identity);
          expect(stale.snapshot.layoutId, controller.snapshot!.layoutId);
          final before = frames;
          controller.forgetPage(0, stale);
          for (var step = 0; step < 100; step++) {
            await Future<void>.value();
          }
          expect(frames, before);
          expect(controller.viewForPage(targetPage + 1), isNull);
          obsolete.close();
        }
        final builds = fixture.cache.layoutBuildCount;
        // Cell disposal acknowledges unmount before releasing actual Surface pins.
        controller.forgetPage(0, original.view);
        if (retirement == 'suspend') controller.suspend();
        if (retirement == 'close') controller.close();
        final expectedRevision = retirement.isEmpty
            ? revision
            : controller.navigationRevision;
        for (final lease in originLeases) {
          lease.release();
        }
        if (retirement.isEmpty) {
          await _until(
            () =>
                controller.viewForPage(targetPage + 1) != null ||
                controller.error != null,
            context:
                'after former mounted page unmounted and released its pins',
          );
          expect(controller.viewForPage(targetPage + 1), isNotNull);
          expect(controller.visiblePageIndex, targetPage);
        } else {
          for (var step = 0; step < 100; step++) {
            await Future<void>.value();
          }
          expect(controller.viewForPage(targetPage + 1), isNull);
          expect(fixture.cache.layoutBuildCount, builds);
          expect(fixture.session.pendingPreparationCount, 0);
        }
        expect(controller.error, isNull);
        expect(controller.navigationRevision, expectedRevision);
        expect(controller.readyTarget, isNull);
      },
    );
  }

  for (final size in [18.5, 17.3, 22.25]) {
    test('fractional ruby children retain complete coverage: $size', () async {
      final fixture = NativeReaderTestFixture(
        '<p style="font-size:${size}px;line-height:1.27">'
        '<ruby>A<rt>x</rt></ruby></p>',
      );
      final controller = _controller(fixture);
      controller.start();
      await _until(
        () => controller.readyTarget != null || controller.error != null,
      );
      expect(controller.error, isNull);
      final delivery = controller.readyTarget!;
      final fragments = delivery.view.takeFragments();
      try {
        final fragment = fragments.single;
        expect(delivery.view.coverage.points, isNotEmpty);
        expect(
          delivery.view.coverage.hasClippedGlyphs,
          isFalse,
          reason:
              'frame=${delivery.view.snapshot.single.fragments.single.height}'
              '/glyphs=${fragment.glyphBoxes(0, fragment.projection.text.length).map((box) => [box.top, box.bottom])}'
              '/lines=${fragment.lines.map((line) => [line.top, line.bottom, line.baseline])}',
        );
        final position = controller.confirmPreparedVisible(
          delivery,
          fragments,
        )!;
        expect(position.isWholeBodyVisible, isTrue);
        expect(position.isBodyEndVisible, isTrue);
      } finally {
        for (final fragment in fragments) {
          fragment.close();
        }
      }
      expect(fixture.cache.activeLeases, 0);
    });
  }

  test('native rounding of fractional row heights cannot falsely hide a fully painted page', () async {
    final fixture = NativeReaderTestFixture(
      '<p style="font-size:18.5px;line-height:1.27">abc<br>def<br>ghi</p>',
      width: 100,
      height: 100,
    );
    final controller = _controller(fixture);
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final delivery = controller.readyTarget!;
    final fragments = delivery.view.takeFragments();
    expect(delivery.view.coverage.points, isNotEmpty);
    expect(delivery.view.coverage.hasClippedGlyphs, isFalse);
    final position = controller.confirmPreparedVisible(delivery, fragments)!;
    expect(position.isWholeBodyVisible, isTrue);
    expect(position.isBodyEndVisible, isTrue);
    for (final fragment in fragments) {
      fragment.close();
    }
    expect(fixture.cache.activeLeases, 0);
  });

  for (final source in [
    '<p style="line-height:.25">X<ruby>A<rt>x</rt></ruby>Z</p>',
    '<p>a</p><p style="line-height:.25">b</p>',
  ]) {
    test(
      'allocated tight font rows retain complete body-end visibility: $source',
      () async {
        final fixture = NativeReaderTestFixture(source, width: 20, height: 100);
        final controller = _controller(fixture);
        controller.start();
        await _until(
          () => controller.readyTarget != null || controller.error != null,
        );
        expect(controller.error, isNull);
        final delivery = controller.readyTarget!;
        final fragments = delivery.view.takeFragments();
        expect(delivery.view.coverage.points, isNotEmpty);
        expect(delivery.view.coverage.hasClippedGlyphs, isFalse);
        final position = controller.confirmPreparedVisible(
          delivery,
          fragments,
        )!;
        expect(position.isWholeBodyVisible, isTrue);
        expect(position.isBodyEndVisible, isTrue);
        for (final fragment in fragments) {
          fragment.close();
        }
      },
    );
  }

  for (final edge in NovelReaderChapterEdge.values) {
    test(
      '$edge provenance requires actual binding and cannot leak to a subsequent turn',
      () async {
        final fixture = NativeReaderTestFixture(
          '<p>abcdefgh</p>',
          width: 20,
          height: 10,
          complete: false,
        );
        final controller = _controller(fixture, entry: edge);
        controller.start();
        await _until(
          () => controller.readyTarget != null || controller.error != null,
        );
        final delivery = controller.readyTarget!;
        expect(delivery.chapterEntryEdge, edge);
        expect(controller.confirmVisible(delivery, []), isNull);
        final leases = delivery.view.takeLeases();
        final position = controller.confirmVisible(delivery, leases)!;
        expect(position.appliedChapterEntry, edge);
        expect(
          controller.requestPage(edge == NovelReaderChapterEdge.start ? 1 : 2),
          isTrue,
        );
        await _until(
          () => controller.readyTarget != null || controller.error != null,
        );
        final next = controller.readyTarget!;
        expect(next.chapterEntryEdge, isNull);
        final nextLeases = next.view.takeLeases();
        expect(
          controller.confirmVisible(next, nextLeases)!.appliedChapterEntry,
          isNull,
        );
        leases.single.release();
        nextLeases.single.release();
      },
    );
  }

  test('chapter confirmation requires live original end leases and explicit visible navigation', () async {
    final fixture = NativeReaderTestFixture(
      '<p>ab</p>',
      width: 100,
      height: 10,
    );
    final controller = _controller(
      fixture,
      position: _position(_anchor(fixture, 0).copyWith(formatVersion: 37)),
    );
    controller.start();
    await _until(() => controller.readyTarget != null);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final original = controller.confirmVisible(delivery, leases)!;
    expect(original.isReadOnlyCompatibilityRestore, isTrue);
    expect(controller.confirmChapterEndNavigation(delivery.view, []), isNull);
    expect(controller.suspend(), isTrue);
    expect(
      controller.confirmChapterEndNavigation(delivery.view, leases),
      isNull,
    );
    controller.resume();
    await _until(() => controller.readyTarget != null);
    final resumed = controller.readyTarget!;
    final resumedLeases = resumed.view.takeLeases();
    controller.confirmVisible(resumed, resumedLeases);
    expect(
      controller.confirmChapterEndNavigation(delivery.view, leases),
      isNull,
    );
    final confirmation = controller.confirmChapterEndNavigation(
      resumed.view,
      resumedLeases,
    )!;
    expect(confirmation.hasUserNavigated, isTrue);
    expect(confirmation.isReadOnlyCompatibilityRestore, isFalse);
    expect(confirmation.isBodyEndVisible, isTrue);
    resumedLeases.single.release();
    expect(
      controller.confirmChapterEndNavigation(resumed.view, resumedLeases),
      isNull,
    );
    leases.single.release();
  });

  test('clipped glyphs cannot provide chapter-end confirmation', () async {
    final fixture = NativeReaderTestFixture('<p>a</p>', width: 1, height: 10);
    final controller = _controller(fixture);
    controller.start();
    await _until(() => controller.readyTarget != null);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final initial = controller.confirmVisible(delivery, leases)!;
    expect(initial.isBodyEndVisible, isFalse);
    expect(
      controller.confirmChapterEndNavigation(delivery.view, leases),
      isNull,
    );
    leases.single.release();
  });

  test('suspended source keeps its cursor and fixed prefix while late idle completion cannot publish', () async {
    final fixture = NativeReaderTestFixture(
      List.filled(20, '<p>abcdefgh</p>').join(),
      width: 20,
      height: 10,
      complete: false,
    );
    final idle = Completer<void>();
    var idleCalls = 0;
    final controller = NovelReaderNativePagedController(
      session: fixture.session,
      anchors: fixture.anchors,
      position: _position(_anchor(fixture, 0)),
      paginationKey: 'geometry',
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      idleScheduler: () {
        idleCalls++;
        return idle.future;
      },
      windowLimits: const NovelReaderNativeViewWindowLimits(radius: 0),
    );
    addTearDown(controller.close);
    controller.start();
    await _until(() => controller.readyTarget != null);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final original = controller.confirmVisible(delivery, leases)!;
    await _until(() => idleCalls > 0);
    final prefix = controller.snapshot!;
    expect(prefix.isComplete, isFalse);
    final nodes = fixture.session.resolvedNodeCount;
    expect(controller.suspend(), isTrue);
    expect(controller.suspend(), isFalse);
    expect(fixture.session.reservedViewLeases, 0);
    idle.complete();
    for (var step = 0; step < 50; step++) {
      await Future<void>.value();
    }
    expect(fixture.session.snapshot.length, prefix.length);
    expect(fixture.session.resolvedNodeCount, nodes);
    expect(leases.every((lease) => lease.isActive), isTrue);
    expect(controller.resume(), isTrue);
    expect(controller.resume(), isFalse);
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    expect(controller.snapshot![0], same(prefix[0]));
    final next = controller.readyTarget!;
    final nextLeases = next.view.takeLeases();
    final resumed = controller.confirmVisible(next, nextLeases)!;
    expect(resumed.anchor.textOffset, original.anchor.textOffset);
    expect(resumed.hasUserNavigated, isFalse);
    await _until(
      () => controller.snapshot!.isComplete || controller.error != null,
    );
    expect(controller.error, isNull);
    expect(controller.snapshot![0], same(prefix[0]));
    expect(fixture.session.resolvedNodeCount, greaterThan(nodes));
    controller.close();
    expect(fixture.session.isClosed, isFalse);
    for (final lease in [...leases, ...nextLeases]) {
      lease.release();
    }
  });

  test('a seek before first paint is retired by suspension and original restore stays passive', () async {
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
    expect(controller.requestPage(3), isTrue);
    expect(controller.suspend(), isTrue);
    expect(controller.requestPage(2), isFalse);
    held = false;
    gate.complete();
    await Future<void>.value();
    expect(controller.readyTarget, isNull);
    controller.resume();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final position = controller.confirmVisible(delivery, leases)!;
    expect(position.pageIndex, 0);
    expect(position.anchor.textOffset, 0);
    expect(position.hasUserNavigated, isFalse);
    leases.single.release();
  });

  test('initial suspension cancels real target timers and closed requests cannot resume', () {
    fakeAsync((clock) {
      final fixture = NativeReaderTestFixture('<p>abc</p>', complete: false);
      final frame = Completer<void>();
      final controller = _controller(
        fixture,
        scheduler: NovelReaderNativeWorkScheduler(
          nextFrame: () => frame.future,
        ),
        performance: const NovelReaderPaginationPerformancePolicy(),
      );
      controller.start();
      clock.elapse(const Duration(seconds: 4));
      expect(controller.suspend(), isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(hours: 1));
      expect(controller.error, isNull);
      expect(controller.readyTarget, isNull);
      expect(controller.snapshot!.length, 0);
      controller.close();
      expect(controller.resume(), isFalse);
      frame.complete();
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 0);
      expect(fixture.session.isClosed, isFalse);
      expect(fixture.parent.isCancelled, isFalse);
    });
  });

  test('a verified retry accepts matching partial prefixes and borrows the old native cache', () async {
    const html = '<p>abcdefgh</p>';
    final old = NativeReaderTestFixture(html, width: 20, height: 10);
    final oldLeases = old.session.preparePageLeases(1);
    final retry = NativeReaderTestFixture(
      html,
      width: 20,
      height: 10,
      complete: false,
      layoutId: 'retry',
      cacheOwner: old.cache,
    );
    final builds = old.cache.layoutBuildCount;
    final controller = NovelReaderNativePagedController(
      session: retry.session,
      anchors: retry.anchors,
      position: _position(_anchor(retry, 3)),
      paginationKey: 'geometry',
      parent: retry.parent,
      previousPrefix: old.session.snapshot,
      previousPaginationKey: 'geometry',
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      performance: const NovelReaderPaginationPerformancePolicy(
        enforceBudgets: false,
      ),
      idleScheduler: () async {},
    );
    addTearDown(controller.close);
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final delivery = controller.readyTarget!;
    expect(delivery.pageIndex, 1);
    final leases = delivery.view.takeLeases();
    expect(controller.confirmVisible(delivery, leases)!.anchor.textOffset, 3);
    expect(leases.single.layout, same(oldLeases.single.layout));
    await _until(
      () => controller.snapshot!.isComplete || controller.error != null,
    );
    expect(controller.error, isNull);
    expect(old.cache.layoutBuildCount, builds);
    controller.close();
    expect(oldLeases.single.isActive, isTrue);
    expect(leases.single.isActive, isTrue);
    expect(old.cache.isClosed, isFalse);
    oldLeases.single.release();
    leases.single.release();
  });

  test('fully hidden source terminates without synthesizing a page or reporting a position', () async {
    final fixture = NativeReaderTestFixture(
      '<p style="display:none">hidden</p>',
      complete: false,
    );
    final controller = _controller(
      fixture,
      entry: NovelReaderChapterEdge.start,
      position: const NovelReaderProgressSnapshot(
        novelId: 'novel',
        episodeId: 'episode',
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 0,
        progressPercent: 0,
      ),
    );
    controller.start();
    await _until(
      () =>
          controller.phase == NovelReaderNativePagedPhase.empty ||
          controller.error != null,
    );
    expect(controller.error, isNull);
    expect(controller.snapshot!.length, 0);
    expect(controller.readyTarget, isNull);
    expect(controller.visiblePageIndex, isNull);
    expect(fixture.session.activeIssuedLeases, 0);
  });

  test('canonical restore shares its proved target and changes no visible position until acknowledged', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final controller = _controller(
      fixture,
      position: _position(_anchor(fixture, 5)),
    );
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final delivery = controller.readyTarget!;
    expect(delivery.pageIndex, 2);
    expect(controller.visiblePageIndex, isNull);
    expect(controller.confirmVisible(delivery, []), isNull);
    final leases = delivery.view.takeLeases();
    final position = controller.confirmVisible(delivery, leases)!;
    expect(position.anchor.textOffset, 5);
    expect(position.isReadOnlyCompatibilityRestore, isFalse);
    expect(position.hasUserNavigated, isFalse);
    expect(position.isWholeBodyVisible, isTrue);
    await _until(
      () => controller.snapshot!.isComplete || controller.error != null,
    );
    expect(controller.error, isNull);
    expect(controller.visiblePageIndex, 2);
    expect(controller.readyTarget, isNull);
    expect(fixture.cache.layoutBuildCount, 1);
    leases.single.release();
    controller.forgetPage(2, delivery.view);
  });

  test('future-format node compatibility stays read-only until real acknowledged navigation', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final saved = _position(_anchor(fixture, 5))
        .copyWith(anchorFormatVersion: 37, isProgressPercentValid: false);
    final controller = _controller(fixture, position: saved);
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final initial = controller.readyTarget!;
    expect(initial.pageIndex, 0);
    final old = initial.view.takeLeases();
    expect(
      controller.confirmVisible(initial, old)!.isReadOnlyCompatibilityRestore,
      isTrue,
    );
    expect(controller.requestPage(1), isTrue);
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    final next = controller.readyTarget!;
    final leases = next.view.takeLeases();
    final actual = controller.confirmVisible(next, leases)!;
    expect(actual.hasUserNavigated, isTrue);
    expect(actual.isReadOnlyCompatibilityRestore, isFalse);
    expect(actual.anchor.hasCanonicalTextOffset, isTrue);
    expect(saved.anchorFormatVersion, 37);
    old.single.release();
    leases.single.release();
  });

  test(
    'a clipped hidden source hint cannot confer canonical restore authority',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>a<span style="display:none">hidden</span>b</p>',
      );
      final controller = _controller(
        fixture,
        position: _position(_anchor(fixture, 3)),
      );
      controller.start();
      await _until(
        () => controller.readyTarget != null || controller.error != null,
      );
      expect(controller.error, isNull);
      final delivery = controller.readyTarget!;
      expect(delivery.isReadOnlyCompatibilityRestore, isTrue);
      final leases = delivery.view.takeLeases();
      expect(
        controller
            .confirmVisible(delivery, leases)!
            .isReadOnlyCompatibilityRestore,
        isTrue,
      );
      leases.single.release();
    },
  );

  test(
    'conversion target remains read-only and does not move again at EOF',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      final controller = _controller(
        fixture,
        conversionAnchor: _anchor(fixture, 5),
      );
      controller.start();
      await _until(
        () => controller.readyTarget != null || controller.error != null,
      );
      final delivery = controller.readyTarget!;
      expect(delivery.pageIndex, 2);
      final leases = delivery.view.takeLeases();
      expect(
        controller
            .confirmVisible(delivery, leases)!
            .isReadOnlyCompatibilityRestore,
        isTrue,
      );
      await _until(
        () => controller.snapshot!.isComplete || controller.error != null,
      );
      expect(controller.visiblePageIndex, 2);
      expect(controller.readyTarget, isNull);
      leases.single.release();
    },
  );

  test('opposite intent cancels missing-page arrival while preserving the old visible page', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefghijklmnop</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    var frozen = false;
    final frames = <Completer<void>>[];
    final controller = _controller(
      fixture,
      entry: NovelReaderChapterEdge.start,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () {
          if (!frozen) return Future.value();
          final frame = Completer<void>();
          frames.add(frame);
          return frame.future;
        },
      ),
    );
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    final initial = controller.readyTarget!;
    final leases = initial.view.takeLeases();
    controller.confirmVisible(initial, leases);
    frozen = true;
    expect(controller.requestPage(6), isTrue);
    expect(controller.visiblePageIndex, 0);
    expect(controller.cancelPendingNavigation(), isTrue);
    frozen = false;
    for (final frame in frames) {
      frame.complete();
    }
    await _until(
      () => controller.snapshot!.isComplete || controller.error != null,
    );
    expect(controller.error, isNull);
    expect(controller.requestedPageIndex, 0);
    expect(controller.visiblePageIndex, 0);
    expect(controller.readyTarget, isNull);
    expect(leases.single.isActive, isTrue);
    leases.single.release();
  });

  test(
    'late old confirmation and released leases cannot confirm a new navigation',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
      );
      final controller = _controller(
        fixture,
        entry: NovelReaderChapterEdge.start,
      );
      controller.start();
      await _until(() => controller.readyTarget != null);
      final old = controller.readyTarget!;
      final oldLeases = old.view.takeLeases();
      controller.requestPage(2);
      expect(controller.confirmVisible(old, oldLeases), isNull);
      await _until(
        () => controller.readyTarget != null || controller.error != null,
      );
      final current = controller.readyTarget!;
      final leases = current.view.takeLeases();
      leases.single.release();
      expect(controller.confirmVisible(current, leases), isNull);
      expect(controller.visiblePageIndex, isNull);
      oldLeases.single.release();
    },
  );

  test(
    'late source failure preserves actual visible leases and accepted prefix',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcd</p><div style="position:absolute">unsupported</div>',
        width: 20,
        height: 10,
        complete: false,
      );
      final controller = _controller(
        fixture,
        entry: NovelReaderChapterEdge.start,
      );
      controller.start();
      await _until(
        () => controller.readyTarget != null || controller.error != null,
      );
      final delivery = controller.readyTarget!;
      final leases = delivery.view.takeLeases();
      controller.confirmVisible(delivery, leases);
      await _until(() => controller.error != null);
      expect(controller.phase, NovelReaderNativePagedPhase.paused);
      expect(controller.visiblePageIndex, 0);
      expect(controller.snapshot!.length, greaterThanOrEqualTo(1));
      expect(leases.single.isActive, isTrue);
      expect(fixture.parent.isCancelled, isFalse);
      expect(fixture.session.isClosed, isFalse);
      leases.single.release();
    },
  );

  test('paused reader navigates only the accepted sealed prefix without resuming source', () async {
    final (fixture: fixture, controller: controller, leases: oldLeases) =
        await _failedReadable();
    final prefix = controller.snapshot!;
    final sourceError = controller.error;
    final builds = fixture.cache.layoutBuildCount;
    expect(prefix.length, greaterThan(1));
    expect(controller.requestPage(prefix.length), isFalse);
    expect(controller.requestPage(-1), isFalse);
    expect(controller.requestPage(1), isTrue);
    expect(controller.visiblePageIndex, 0);
    await _until(() => controller.readyTarget != null);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final position = controller.confirmVisible(delivery, leases)!;
    expect(position.pageIndex, 1);
    expect(position.hasUserNavigated, isTrue);
    expect(position.isReadOnlyCompatibilityRestore, isFalse);
    expect(position.isPageCountFinal, isFalse);
    expect(controller.phase, NovelReaderNativePagedPhase.paused);
    expect(controller.error, same(sourceError));
    expect(controller.snapshot, same(prefix));
    expect(fixture.cache.layoutBuildCount, builds);
    expect(oldLeases.single.isActive, isTrue);
    leases.single.release();
    oldLeases.single.release();
  });

  test('paused pending navigation retires on cancellation and rejects the late target', () async {
    var held = false;
    final frame = Completer<void>();
    final (
      fixture: fixture,
      controller: controller,
      leases: oldLeases,
    ) = await _failedReadable(
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) await frame.future;
        },
      ),
    );
    held = true;
    expect(controller.requestPage(1), isTrue);
    expect(controller.cancelPendingNavigation(), isTrue);
    expect(controller.visiblePageIndex, 0);
    expect(controller.requestPage(2), isTrue);
    held = false;
    frame.complete();
    await _until(() => controller.readyTarget != null);
    final target = controller.readyTarget!;
    expect(target.pageIndex, 2);
    final leases = target.view.takeLeases();
    expect(controller.confirmVisible(target, leases)!.pageIndex, 2);
    expect(controller.phase, NovelReaderNativePagedPhase.paused);
    leases.single.release();
    oldLeases.single.release();
    controller.close();
    expect(fixture.session.reservedViewLeases, 0);
  });

  test('paused prefix preparation keeps a bounded target deadline and cleans reservations', () async {
    var held = false;
    final frame = Completer<void>();
    final (
      fixture: fixture,
      controller: controller,
      leases: oldLeases,
    ) = await _failedReadable(
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          if (held) await frame.future;
        },
      ),
      performance: const NovelReaderPaginationPerformancePolicy(
        targetPageWait: Duration(milliseconds: 100),
      ),
    );
    final error = controller.error;
    final prefix = controller.snapshot;
    held = true;
    final expired = controller.changes.firstWhere(
      (_) => !identical(controller.error, error),
    );
    expect(controller.requestPage(1), isTrue);
    await expired;
    expect(
      controller.error,
      isA<NovelReaderPaginationException>().having(
        (error) => error.code,
        'code',
        'targetPageWaitExceeded',
      ),
    );
    expect(controller.snapshot, same(prefix));
    expect(controller.visiblePageIndex, 0);
    expect(oldLeases.single.isActive, isTrue);
    expect(fixture.session.reservedViewLeases, 0);
    held = false;
    frame.complete();
    oldLeases.single.release();
  });

  test('chapter-end entry waits for EOF and does not turn chapters when target is absent', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final controller = _controller(fixture, entry: NovelReaderChapterEdge.end);
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.snapshot!.isComplete, isTrue);
    final delivery = controller.readyTarget!;
    expect(delivery.pageIndex, 3);
    final leases = delivery.view.takeLeases();
    expect(
      controller.confirmVisible(delivery, leases)!.hasUserNavigated,
      isTrue,
    );
    expect(controller.requestPage(4), isFalse);
    expect(controller.visiblePageIndex, 3);
    leases.single.release();
  });

  test(
    'retry mismatch cannot replace the old visible page or close its owner',
    () async {
      const html = '<p>ab</p><p>cd</p>';
      final old = NativeReaderTestFixture(html, width: 100, height: 40);
      final oldLeases = old.session.preparePageLeases(0);
      final retry = NativeReaderTestFixture(
        html,
        width: 100,
        height: 40,
        textScaler: const TextScaler.linear(1.1),
        complete: false,
        layoutId: 'retry',
      );
      final controller = NovelReaderNativePagedController(
        session: retry.session,
        anchors: retry.anchors,
        position: _position(_anchor(retry, 0)),
        paginationKey: 'geometry',
        parent: retry.parent,
        previousPrefix: old.session.snapshot,
        previousPaginationKey: 'geometry',
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
        performance: const NovelReaderPaginationPerformancePolicy(
          enforceBudgets: false,
        ),
        idleScheduler: () async {},
      );
      addTearDown(controller.close);
      controller.start();
      await _until(() => controller.error != null);
      expect(
        controller.error,
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'paginationPrefixMismatch',
        ),
      );
      expect(controller.readyTarget, isNull);
      expect(controller.snapshot!.length, 0);
      expect(controller.requestPage(0), isFalse);
      expect(oldLeases.every((lease) => lease.isActive), isTrue);
      for (final lease in oldLeases) {
        lease.release();
      }
    },
  );

  test('target expiry pauses the actual source request without closing session or parent', () {
    fakeAsync((clock) {
      final fixture = NativeReaderTestFixture('<p>abc</p>', complete: false);
      final frame = Completer<void>();
      final controller = NovelReaderNativePagedController(
        session: fixture.session,
        anchors: fixture.anchors,
        position: _position(_anchor(fixture, 0)),
        paginationKey: 'geometry',
        parent: fixture.parent,
        scheduler: NovelReaderNativeWorkScheduler(
          nextFrame: () => frame.future,
        ),
      );
      controller.start();
      clock.elapse(const Duration(seconds: 5));
      expect(controller.phase, NovelReaderNativePagedPhase.paused);
      expect(
        controller.error,
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'targetPageWaitExceeded',
        ),
      );
      expect(fixture.session.isClosed, isFalse);
      expect(fixture.parent.isCancelled, isFalse);
      expect(fixture.session.reservedViewLeases, 0);
      expect(clock.nonPeriodicTimerCount, 0);
      controller.close();
      frame.complete();
      clock.flushMicrotasks();
    });
  });

  test('clipped page content never claims whole-body visibility or canonical authority', () async {
    final fixture = NativeReaderTestFixture(
      '<p>a</p>',
      width: 1,
      height: 10,
      complete: false,
    );
    final controller = _controller(
      fixture,
      entry: NovelReaderChapterEdge.start,
    );
    controller.start();
    await _until(
      () => controller.readyTarget != null || controller.error != null,
    );
    expect(controller.error, isNull);
    final delivery = controller.readyTarget!;
    final leases = delivery.view.takeLeases();
    final position = controller.confirmVisible(delivery, leases)!;
    expect(position.isWholeBodyVisible, isFalse);
    expect(position.isBodyEndVisible, isFalse);
    expect(position.isReadOnlyCompatibilityRestore, isTrue);
    expect(position.anchor.hasCanonicalTextOffset, isFalse);
    leases.single.release();
  });

  testWidgets(
    'native reader assembly confirms only an actual mounted frame and reuses one layout',
    (tester) async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefgh</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      final controller = _controller(
        fixture,
        position: _position(_anchor(fixture, 5)),
      );
      final reports = <NovelReaderPaginationPosition>[];
      controller.start();
      expect(reports, isEmpty);
      await tester.pumpWidget(_MountedReader(controller, reports));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reports, hasLength(1));
      expect(reports.single.pageIndex, 2);
      expect(reports.single.anchor.textOffset, 5);
      expect(reports.single.hasUserNavigated, isFalse);
      expect(fixture.cache.layoutBuildCount, 1);
      expect(controller.requestPage(3), isTrue);
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.last.pageIndex, 3);
      expect(reports.last.hasUserNavigated, isTrue);
      expect(fixture.cache.layoutBuildCount, 1);
      controller.close();
      expect(fixture.session.activeIssuedLeases, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

/// App-owned integration harness. The production viewport still supplies its
/// own gesture, locality, old-layout retention and owner/authority adapters.
final class _MountedReader extends StatefulWidget {
  const _MountedReader(this.controller, this.reports);
  final NovelReaderNativePagedController controller;
  final List<NovelReaderPaginationPosition> reports;
  @override
  State<_MountedReader> createState() => _MountedReaderState();
}

final class _MountedReaderState extends State<_MountedReader> {
  StreamSubscription<void>? _subscription;
  NovelReaderNativePageDelivery? _delivery;
  List<ForumBodyParagraphLease> _leases = const [];
  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.controller.readyTarget;
    if (proposal != null &&
        !identical(proposal, _delivery) &&
        proposal.view.isReady) {
      _delivery = proposal;
      _leases = proposal.view.takeLeases();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_delivery, proposal)) return;
        final report = widget.controller.confirmVisible(proposal, _leases);
        if (report != null) widget.reports.add(report);
      });
    }
    final delivery = _delivery;
    if (delivery == null) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 20,
          height: 10,
          child: ForumBodyTextPageSurface(
            snapshot: delivery.view.snapshot,
            pageIndex: delivery.pageIndex,
            layoutId: delivery.view.snapshot.layoutId,
            leases: _leases,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    final delivery = _delivery;
    if (delivery != null) {
      widget.controller.forgetPage(delivery.pageIndex, delivery.view);
    }
    super.dispose();
  }
}
