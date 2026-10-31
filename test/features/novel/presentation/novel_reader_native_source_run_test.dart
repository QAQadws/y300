import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_view.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_view_job.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_hint_search.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_restore_cursor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_source_run.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_demand.dart';

import '../test_support/native_reader_test_fixture.dart';

Future<void> _flush() async {
  for (var turn = 0; turn < 25; turn++) {
    await Future<void>.value();
  }
}

final _cancelled = isA<NovelReaderPaginationException>().having(
  (error) => error.code,
  'code',
  'paginationCancelled',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NovelReaderPaginationDemand demand() {
    final value = NovelReaderPaginationDemand(lookAhead: 0);
    addTearDown(value.dispose);
    return value;
  }

  test('cheap foreground publications reuse the bounded frame slice instead of waiting per page', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefghijklmnopqrst</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    var frames = 0;
    final publications = <(int, int)>[];
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      // A generous test-only clock makes the deterministic work-count bound
      // observable; production retains its existing 3ms recovery/work policy.
      limits: const NovelReaderNativeSourceRunLimits(
        frameBudget: Duration(seconds: 1),
        maxStepsPerFrame: 64,
      ),
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          frames++;
        },
      ),
      onPublication: (prefix, _) {
        publications.add((prefix.length, frames));
      },
    );
    addTearDown(run.close);
    final result = await run.run();
    expect(result.length, 10);
    expect(frames, 1);
    expect(publications.map((entry) => entry.$1), [
      ...List.generate(10, (index) => index + 1),
      10,
    ]);
    expect(publications.every((entry) => entry.$2 == 1), isTrue);
    expect(fixture.cache.layoutBuildCount, 1);
  });

  test('source step limits still force frames even with fast publication callbacks', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefghijklmnopqrst</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    var frames = 0;
    final workDemand = NovelReaderPaginationDemand(lookAhead: 0);
    addTearDown(workDemand.dispose);
    final publications = <int>[];
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: workDemand,
      parent: fixture.parent,
      limits: const NovelReaderNativeSourceRunLimits(
        frameBudget: Duration(seconds: 1),
        maxStepsPerFrame: 1,
      ),
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          frames++;
        },
      ),
      onPublication: (_, _) {
        publications.add(frames);
      },
    );
    addTearDown(run.close);
    await run.run();
    expect(frames, greaterThanOrEqualTo(11));
    expect(publications.toSet().length, publications.length);
    expect(fixture.cache.layoutBuildCount, 1);
  });

  test('source starts after a frame and emits fixed stable prefixes through actual EOF', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final firstFrame = Completer<void>();
    var frames = 0;
    final prefixes = <ForumBodyTextPageSnapshot>[];
    NovelReaderPaginationCancellationToken? work;
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () {
          frames++;
          return frames == 1 ? firstFrame.future : Future.value();
        },
      ),
      onPublication: (snapshot, token) {
        expect(token.isCancelled, isFalse);
        work = token;
        prefixes.add(snapshot);
      },
    );
    addTearDown(run.close);
    final future = run.run();
    expect(run.run(), same(future));
    await _flush();
    expect(fixture.session.resolvedNodeCount, 0);
    expect(prefixes, isEmpty);
    firstFrame.complete();
    final result = await future;
    expect(result.isComplete, isTrue);
    expect(prefixes.map((prefix) => prefix.length), [1, 2, 3, 3]);
    expect(prefixes.first.length, 1);
    expect(prefixes.first.isComplete, isFalse);
    expect(prefixes.last.isComplete, isTrue);
    expect(run.state, NovelReaderNativeSourceRunState.complete);
    expect(work!.isCancelled, isTrue);
    expect(fixture.parent.isCancelled, isFalse);
    expect(fixture.session.isClosed, isFalse);
    expect(() => run.run(), throwsStateError);
  });

  test('publication work is serial and a layout-owned view survives source completion', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final release = Completer<void>();
    final admitted = Completer<void>();
    var publications = 0;
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (snapshot, token) async {
        if (++publications != 1) return;
        admitted.complete();
        await token.waitFor(release.future);
      },
    );
    addTearDown(run.close);
    final future = run.run();
    await admitted.future;
    final builds = fixture.cache.layoutBuildCount;
    final frames = run.framesWaited;
    await _flush();
    expect(publications, 1);
    expect(fixture.session.snapshot.length, 1);
    expect(run.framesWaited, frames);
    final view = await NovelReaderNativePageViewJob(
      session: fixture.session,
      anchors: fixture.anchors,
      pageIndex: 0,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    ).run();
    expect(fixture.cache.layoutBuildCount, builds);
    release.complete();
    await future;
    expect(view.isReady, isTrue);
    view.close();
  });

  test('stable publication waits for existing idle demand and promotion resumes the same source', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefgh</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final idle = Completer<void>();
    final workDemand = NovelReaderPaginationDemand(
      lookAhead: 0,
      idleScheduler: () => idle.future,
    );
    addTearDown(workDemand.dispose);
    workDemand.update(targetPending: false, pageIndex: 0);
    var publications = 0;
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: workDemand,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {
        publications++;
      },
    );
    addTearDown(run.close);
    final future = run.run();
    await _flush();
    expect(workDemand.isDeferring, isTrue);
    expect(publications, 1);
    final frames = run.framesWaited;
    await _flush();
    expect(run.framesWaited, frames);
    workDemand.update(targetPending: true, pageIndex: 3);
    final result = await future;
    expect(result.length, 4);
    expect(workDemand.isDeferring, isFalse);
    expect(fixture.session.isComplete, isTrue);
    idle.complete();
  });

  test('pinned source work waits for a real release without requesting extra frames', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      cacheEntries: 1,
      width: 20,
      height: 10,
      complete: false,
    );
    final foreign = fixture.pinForeign();
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {},
    );
    addTearDown(run.close);
    final future = run.run();
    await _flush();
    expect(fixture.session.waitingForLayoutBudget, isTrue);
    final frames = run.framesWaited;
    final builds = fixture.cache.layoutBuildCount;
    await _flush();
    expect(run.framesWaited, frames);
    expect(fixture.cache.layoutBuildCount, builds);
    foreign.release();
    expect((await future).length, 3);
  });

  test('closing a pending frame stops only this run and observes late frame failure', () async {
    final fixture = NativeReaderTestFixture('<p>abcdef</p>', complete: false);
    final frame = Completer<void>();
    var published = 0;
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () => frame.future),
      onPublication: (_, _) {
        published++;
      },
    );
    final result = expectLater(run.run(), throwsA(_cancelled));
    run.close();
    await result;
    expect(published, 0);
    expect(fixture.parent.isCancelled, isFalse);
    expect(fixture.session.isClosed, isFalse);
    frame.completeError(StateError('late frame'));
    await _flush();
    final retry = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {},
    );
    addTearDown(retry.close);
    expect((await retry.run()).isComplete, isTrue);
  });

  test('retirement interrupts a pending frame even while the borrowed cache stays open', () async {
    final fixture = NativeReaderTestFixture('<p>abcdef</p>', complete: false);
    final frame = Completer<void>();
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () => frame.future),
      onPublication: (_, _) {},
    );
    final result = expectLater(run.run(), throwsA(_cancelled));
    fixture.session.close();
    await result;
    expect(fixture.cache.isClosed, isFalse);
    expect(fixture.parent.isCancelled, isFalse);
    frame.complete();
  });

  test('publication failure preserves published pages and never retries its callback', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    var publications = 0;
    final error = StateError('consumer failed');
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {
        publications++;
        throw error;
      },
    );
    addTearDown(run.close);
    await expectLater(run.run(), throwsA(same(error)));
    expect(run.state, NovelReaderNativeSourceRunState.failed);
    expect(publications, 1);
    expect(fixture.session.snapshot.length, 1);
    final view = await NovelReaderNativePageViewJob(
      session: fixture.session,
      anchors: fixture.anchors,
      pageIndex: 0,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    ).run();
    view.close();
    expect(fixture.session.isClosed, isFalse);
    expect(fixture.parent.isCancelled, isFalse);
  });

  test('invalid step budgets are rejected before acquiring any demand or source work', () {
    final fixture = NativeReaderTestFixture('<p>abc</p>', complete: false);
    final workDemand = demand();
    for (final limits in [
      const NovelReaderNativeSourceRunLimits(frameBudget: Duration.zero),
      const NovelReaderNativeSourceRunLimits(maxStepsPerFrame: 0),
      const NovelReaderNativeSourceRunLimits(eventsPerStep: 0),
      const NovelReaderNativeSourceRunLimits(linesPerStep: 0),
    ]) {
      expect(
        () => NovelReaderNativeSourceRun(
          session: fixture.session,
          demand: workDemand,
          parent: fixture.parent,
          onPublication: (_, _) {},
          limits: limits,
        ),
        throwsArgumentError,
      );
    }
    expect(fixture.session.resolvedNodeCount, 0);
    expect(workDemand.isDeferring, isFalse);
  });

  test('source publications restore only the hinted target view and keep that choice at EOF', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdefghij</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final target = fixture.anchors.segments.first.projection.baseAnchor
        .copyWith(textOffset: 5);
    final restore = NovelReaderNativeRestoreCursor(
      identity: fixture.anchors.identity,
      layoutId: 'generation-a',
      episodeId: 'episode',
      paginationKey: 'native-geometry',
      position: NovelReaderProgressSnapshot(
        novelId: 'novel',
        episodeId: 'episode',
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 99,
        anchorNodeId: target.nodeId,
        anchorFormatVersion: target.formatVersion,
        anchorTextIdentity: target.textIdentity,
        anchorTextOffset: 5,
        progressPercent: .95,
        isProgressPercentValid: true,
      ),
    );
    addTearDown(restore.close);
    final workDemand = NovelReaderPaginationDemand(
      lookAhead: 0,
      idleScheduler: () async {},
    );
    addTearDown(workDemand.dispose);
    var scanned = 0;
    NovelReaderNativePageView? visible;
    final prepared = <int>[];
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: workDemand,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (snapshot, _) async {
        if (!restore.isResolved) {
          final search = NovelReaderNativePageHintSearch(
            snapshot: snapshot,
            layoutId: 'generation-a',
            anchors: fixture.anchors,
            anchor: target,
            startPageIndex: scanned,
          );
          while (!search.isComplete) {
            search.advance(maxPages: 4, maxFragments: 8);
            for (final hint in search.takeCandidates()) {
              prepared.add(hint.pageIndex);
              final view = await NovelReaderNativePageViewJob(
                session: fixture.session,
                anchors: fixture.anchors,
                pageIndex: hint.pageIndex,
                parent: fixture.parent,
                scheduler: NovelReaderNativeWorkScheduler(
                  nextFrame: () async {},
                ),
              ).run();
              restore.observe(snapshot: snapshot, coverage: view.coverage);
              if (restore.resolve(snapshot) != null) {
                visible = view;
                break;
              }
              view.close();
            }
          }
          scanned = search.nextPageIndex;
          search.close();
        }
        final result = restore.resolve(snapshot);
        workDemand.update(
          targetPending: result == null,
          pageIndex: result?.pageIndex ?? 0,
          requireComplete: restore.requiresCompletePageCount,
        );
      },
    );
    addTearDown(run.close);
    final finalPrefix = await run.run();
    expect(prepared, [2]);
    expect(restore.resolve(finalPrefix)!.pageIndex, 2);
    expect(
      restore.resolve(finalPrefix)!.isReadOnlyCompatibilityRestore,
      isFalse,
    );
    expect(visible!.isReady, isTrue);
    expect(visible!.coverage.locate(target), isNotNull);
    expect(fixture.cache.layoutBuildCount, 1);
    visible!.close();
    expect(fixture.session.activeIssuedLeases, 0);
  });

  test('late callback failure is observed after cancellation and cannot publish another page', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final release = Completer<void>();
    final called = Completer<void>();
    var publications = 0;
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {
        publications++;
        called.complete();
        return release.future;
      },
    );
    final result = expectLater(run.run(), throwsA(_cancelled));
    await called.future;
    run.close();
    await result;
    release.completeError(StateError('late callback'));
    await _flush();
    expect(publications, 1);
    expect(fixture.session.snapshot.length, 1);
  });

  test('an outside source advance during publication fails without rewinding stable pages', () async {
    final fixture = NativeReaderTestFixture(
      '<p>abcdef</p>',
      width: 20,
      height: 10,
      complete: false,
    );
    final run = NovelReaderNativeSourceRun(
      session: fixture.session,
      demand: demand(),
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      onPublication: (_, _) {
        fixture.finishSource();
      },
    );
    addTearDown(run.close);
    await expectLater(run.run(), throwsStateError);
    expect(fixture.session.snapshot.length, 3);
    expect(fixture.session.isComplete, isTrue);
    expect(run.state, NovelReaderNativeSourceRunState.failed);
  });
}
