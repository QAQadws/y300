import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_reading_session.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';

const _a = NovelSourceReadingChapter(
  episodeId: 'a',
  sourceTid: '100',
  sourcePid: '101',
);
const _b = NovelSourceReadingChapter(
  episodeId: 'b',
  sourceTid: '100',
  sourcePid: '102',
);

void main() {
  test(
    'catalog mapping is immutable, exact and rejects ambiguous ownership',
    () {
      final chapters = [_a, _b];
      final context = NovelSourceReadingContext(
        novelId: 'novel',
        chapters: chapters,
        initialEpisodeId: 'a',
      );
      chapters.clear();
      expect(context.chapterForSource(' 100 ', '101'), same(_a));
      expect(context.initialChapter, same(_a));
      expect(context.chapterForSource('other', '101'), isNull);
      expect(() => context.chapters.clear(), throwsUnsupportedError);
      final ambiguous = NovelSourceReadingContext(
        novelId: 'novel',
        chapters: [
          _a,
          const NovelSourceReadingChapter(
            episodeId: 'other',
            sourceTid: '100',
            sourcePid: '101',
          ),
          _b,
          const NovelSourceReadingChapter(
            episodeId: 'missing',
            sourceTid: '100',
            sourcePid: null,
          ),
        ],
        initialEpisodeId: 'a',
      );
      expect(ambiguous.chapterForSource('100', '101'), isNull);
      expect(ambiguous.initialChapter, isNull);
      expect(ambiguous.chapterForSource('100', '102'), same(_b));
    },
  );

  test(
    'batch load failure disables tracking while leaving browsing usable',
    () async {
      final h = _Harness()..repository.failLoad = true;
      await h.start();
      expect(h.adapter.tracks('100', '101'), false);
      expect(h.restore(), isNull);
      h.report([_sample()], navigation: 1);
      await h.adapter.flush();
      expect(h.repository.positions, isEmpty);
      expect(h.notifications, 0);
      await h.adapter.prepare();
      expect(h.repository.loads, 1);
      h.dispose();
    },
  );

  test(
    'restore is initial PID only, issued once and preserves future metadata',
    () async {
      final old = _oldProgress(.42, basis: 'futureBasis');
      final h = _Harness()..repository.positions['a'] = old;
      await h.start();
      expect(
        h.adapter.restoreTarget(tid: '100', pid: '102', bodyIdentity: 'b'),
        isNull,
      );
      expect(h.restore()!.fraction, .42);
      expect(h.restore(), isNull);
      h.report([_sample(top: -252)]);
      await h.adapter.flush();
      expect(h.repository.positions['a'], same(old));
      expect(h.repository.writes, 0);
      h.dispose();
    },
  );

  test(
    'invalid or unknown zero fraction only locates the body and stays read-only',
    () async {
      for (final progress in [
        _oldProgress(0, valid: null),
        _oldProgress(.5, valid: false),
        _oldProgress(double.nan),
        _oldProgress(1.5),
      ]) {
        final h = _Harness()..repository.positions['a'] = progress;
        await h.start();
        expect(h.restore(), isNull);
        h.report([_sample()]);
        await h.adapter.flush();
        expect(h.repository.positions['a'], same(progress));
        h.dispose();
      }
    },
  );

  test(
    'real navigation writes body fraction and clears stale reader auxiliaries',
    () async {
      final h = _Harness()..repository.positions['a'] = _oldProgress(.1);
      await h.start();
      h.report([_sample(top: -300)], navigation: 1);
      await h.adapter.flush();
      final saved = h.repository.positions['a']!;
      expect(saved.progressPercent, .5);
      expect(saved.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
      expect(saved.isProgressPercentValid, true);
      expect(saved.flowMode, NovelReaderFlowMode.vertical);
      expect(saved.scrollOffset, 0);
      expect(saved.pageIndex, 0);
      expect(saved.pageCount, isNull);
      expect(saved.anchorNodeId, isNull);
      expect(saved.anchorTextOffset, 0);
      expect(saved.anchorFormatVersion, 0);
      expect(saved.anchorTextIdentity, isNull);
      expect(saved.paginationKey, isNull);
      h.dispose();
    },
  );

  test(
    'negative PID-centered coordinates and loading geometry remain bounded',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample(top: -300, ready: false)]);
      await h.adapter.flush();
      expect(h.repository.positions, isEmpty);
      h.report([_sample(top: -300)]);
      await h.adapter.flush();
      expect(h.repository.positions['a']!.progressPercent, .5);
      h.report([_sample(top: -500)], navigation: 1);
      await h.adapter.flush();
      expect(
        h.repository.positions['a']!.progressPercent,
        closeTo(5 / 6, .0001),
      );
      h.dispose();
    },
  );

  test(
    'comments freeze the last body position and unbound posts never advance it',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample(top: -120)]);
      await h.adapter.flush();
      final saved = h.repository.positions['a']!;
      h.report([_sample(pid: '999', top: -600)], navigation: 1);
      h.report([], navigation: 2);
      await h.adapter.flush();
      expect(h.repository.positions['a']!.progressPercent, .2);
      expect(h.repository.positions['a'], same(saved));
      expect(h.repository.positions.keys, ['a']);
      h.dispose();
    },
  );

  test(
    'current body at the reading line wins over lower chapters in one viewport',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample(top: -100)]);
      await h.adapter.flush();
      h.report([
        _sample(top: -300),
        _sample(pid: '102', identity: 'body-b', top: 700),
      ], navigation: 1);
      await h.adapter.flush();
      expect(h.repository.positions.keys, ['a']);
      expect(h.repository.positions['a']!.progressPercent, .5);
      h.dispose();
    },
  );

  test(
    'fast cross-chapter navigation flushes each confirmed position before switching',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample(top: -240)], navigation: 1);
      await Future<void>.value();
      await Future<void>.value();
      h.report([
        _sample(pid: '102', identity: 'body-b', top: -120),
      ], navigation: 2);
      await h.adapter.flush();
      expect(h.repository.positions['a']!.progressPercent, .4);
      expect(h.repository.positions['b']!.progressPercent, .2);
      expect(h.repository.recent, 'b');
      h.dispose();
    },
  );

  test(
    'suspending a gated chapter switch flushes old position and admits no hidden body',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.start());
        clock.flushMicrotasks();
        h.report([_sample()]);
        clock.flushMicrotasks();
        unawaited(h.adapter.flush());
        clock.flushMicrotasks();
        final release = Completer<void>();
        var oldWriteEntered = false;
        h.repository.beforeWrite = (progress, _) async {
          if (progress.episodeId == 'a' && progress.progressPercent == .4) {
            oldWriteEntered = true;
            await release.future;
          }
        };
        h.report([_sample(top: -240)], navigation: 1);
        clock.flushMicrotasks();
        h.report([
          _sample(pid: '102', identity: 'body-b', height: 200, extent: 200),
        ], navigation: 2);
        clock.flushMicrotasks();
        expect(oldWriteEntered, true);
        h.adapter.suspendForFlush();
        var hideFlushFinished = false;
        unawaited(h.adapter.flush().then((_) => hideFlushFinished = true));
        h.report([
          _sample(pid: '102', identity: 'body-b', height: 200, extent: 200),
        ], navigation: 3);
        release.complete();
        clock.flushMicrotasks();
        expect(hideFlushFinished, true);
        clock.elapse(const Duration(milliseconds: 500));
        clock.flushMicrotasks();
        expect(h.repository.positions.keys, ['a']);
        expect(h.repository.positions['a']!.progressPercent, .4);
        expect(h.repository.completed, isEmpty);
        expect(h.repository.recent, 'a');
        h.adapter.onVisibility(frontmost: false, resumed: true);
        h.dispose();
      });
    },
  );

  test(
    'resume before an old flush finishes cannot revive retired viewport facts',
    () {
      for (final publishFreshFacts in [false, true]) {
        fakeAsync((clock) {
          final h = _Harness();
          unawaited(h.start());
          clock.flushMicrotasks();
          h.report([_sample()]);
          clock.flushMicrotasks();
          unawaited(h.adapter.flush());
          clock.flushMicrotasks();
          final release = Completer<void>();
          var gated = false;
          h.repository.beforeWrite = (progress, _) async {
            if (progress.episodeId == 'a' && progress.progressPercent == .4) {
              gated = true;
              await release.future;
            }
          };
          h.report([_sample(top: -240)], navigation: 1);
          clock.flushMicrotasks();
          h.report([
            _sample(pid: '102', identity: 'body-b', height: 200, extent: 200),
          ], navigation: 2);
          clock.flushMicrotasks();
          expect(gated, true);
          h.adapter.suspendForFlush();
          h.adapter.onVisibility(frontmost: true, resumed: true);
          if (publishFreshFacts) {
            h.report([
              _sample(pid: '102', identity: 'body-b', top: -360),
            ], navigation: 3);
          }
          release.complete();
          clock.flushMicrotasks();
          unawaited(h.adapter.flush());
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 500));
          clock.flushMicrotasks();
          expect(h.repository.positions['a']!.progressPercent, .4);
          expect(
            h.repository.positions['b']?.progressPercent,
            publishFreshFacts ? .6 : isNull,
          );
          expect(h.repository.completed, isEmpty);
          h.dispose();
        });
      }
    },
  );

  test(
    'layout compensation alone cannot rewrite the last genuine position',
    () async {
      final h = _Harness()..repository.positions['a'] = _oldProgress(.1);
      await h.start();
      h.report([_sample(top: -240)], navigation: 1);
      await h.adapter.flush();
      h.report([_sample(top: -360, geometry: 'layout-b')], navigation: 1);
      await h.adapter.flush();
      expect(h.repository.positions['a']!.progressPercent, .4);
      h.dispose();
    },
  );

  test(
    'same-revision compensation while flushing cannot replace navigation geometry',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample()]);
      await h.adapter.flush();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.repository.beforeWrite = (progress, _) async {
        if (progress.episodeId == 'a' && progress.progressPercent == .4) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
      };
      h.report([_sample(top: -240)], navigation: 1);
      await Future<void>.value();
      await Future<void>.value();
      h.report([
        _sample(pid: '102', identity: 'body-b', top: -60),
      ], navigation: 2);
      await entered.future;
      h.report([
        _sample(
          pid: '102',
          identity: 'body-b',
          top: -300,
          geometry: 'new-layout',
        ),
      ], navigation: 2);
      release.complete();
      await h.adapter.flush();
      expect(h.repository.positions['a']!.progressPercent, .4);
      expect(h.repository.positions['b']!.progressPercent, .1);
      h.dispose();
    },
  );

  test(
    'programmatic content refresh does not reuse an older navigation revision',
    () async {
      final h = _Harness()..repository.positions['a'] = _oldProgress(.1);
      await h.start();
      h.report([_sample(top: -240)], navigation: 1);
      await h.adapter.flush();
      final saved = h.repository.positions['a']!;
      h.adapter.onContentChanged('new-page');
      h.report(
        [_sample(top: -540, identity: 'new-body')],
        navigation: 1,
        content: 'new-page',
      );
      await h.adapter.flush();
      expect(h.repository.positions['a'], same(saved));
      expect(saved.progressPercent, .4);
      h.dispose();
    },
  );

  test(
    'page replacement, hidden reports and disposal reject late positions',
    () async {
      final h = _Harness();
      await h.start();
      h.report([_sample()], content: 'old');
      await h.adapter.flush();
      expect(h.repository.positions, isEmpty);
      h.adapter.onContentChanged('new');
      h.report([_sample(top: -200)]);
      await h.adapter.flush();
      expect(h.repository.positions, isEmpty);
      h.adapter.onVisibility(frontmost: false, resumed: true);
      h.report([_sample(top: -200)], content: 'new', navigation: 2);
      await h.adapter.flush();
      expect(h.repository.positions, isEmpty);
      h.dispose();
      expect(h.adapter.tracks('100', '101'), false);
    },
  );

  test(
    'queued position and atomic completion cannot survive a manual reset',
    () async {
      final h = _Harness();
      await h.start();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.repository.beforeWrite = (_, _) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      h.report([_sample(top: -300)], navigation: 1);
      final save = h.adapter.flush();
      await entered.future;
      h.barrier.invalidate('novel', 'a');
      await h.repository.resetChapter(novelId: 'novel', episodeId: 'a');
      release.complete();
      await save;
      expect(h.repository.positions, isEmpty);
      expect(h.notifications, 0);
      h.dispose();
    },
  );

  test('position failures keep the old row and do not loop retries', () async {
    final old = _oldProgress(.1);
    final h = _Harness()..repository.positions['a'] = old;
    await h.start();
    h.repository.failWrite = true;
    h.report([_sample(top: -300)], navigation: 1);
    await h.adapter.flush();
    expect(h.repository.positions['a'], same(old));
    expect(h.notifications, 0);
    h.dispose();
  });

  test(
    'short ready body confirms at 250ms but restore and body-end entries do not',
    () {
      for (final entry in [
        NovelReadingSessionEntry.firstStart,
        NovelReadingSessionEntry.explicitStart,
        NovelReadingSessionEntry.resume,
        NovelReadingSessionEntry.bodyEnd,
      ]) {
        fakeAsync((clock) {
          final h = _Harness(entry: entry);
          if (entry == NovelReadingSessionEntry.resume) {
            h.repository.positions['a'] = _oldProgress(0);
          }
          unawaited(h.start());
          clock.flushMicrotasks();
          h.report([_sample(height: 200, extent: 200)]);
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 249));
          clock.flushMicrotasks();
          expect(h.repository.completed, isEmpty);
          clock.elapse(const Duration(milliseconds: 1));
          clock.flushMicrotasks();
          expect(
            h.repository.completed,
            entry == NovelReadingSessionEntry.firstStart ||
                    entry == NovelReadingSessionEntry.explicitStart
                ? {'a'}
                : isEmpty,
          );
          h.dispose();
        });
      }
    },
  );

  test(
    'images, collapsed end, scrolling and visibility cancel premature completion',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.start());
        clock.flushMicrotasks();
        h.report([_sample(height: 200, extent: 200, ready: false)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(h.repository.completed, isEmpty);
        h.report([_sample(height: 200, extent: 200, finalBoundary: false)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(h.repository.completed, isEmpty);
        h.report([_sample(height: 200, extent: 200)], idle: false);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(h.repository.completed, isEmpty);
        h.report([_sample(height: 200, extent: 200)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 200));
        h.adapter.cancelPendingCompletion();
        h.adapter.onVisibility(frontmost: true, resumed: false);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(h.repository.completed, isEmpty);
        h.dispose();
      });
    },
  );

  test(
    'long body needs genuine movement and completion uses body end only',
    () {
      fakeAsync((clock) {
        final h = _Harness();
        unawaited(h.start());
        clock.flushMicrotasks();
        h.report([_sample(top: -600)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 300));
        clock.flushMicrotasks();
        expect(h.repository.completed, isEmpty);
        h.report([_sample(top: -600)], navigation: 1);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(h.repository.completed, {'a'});
        h.report([], navigation: 2);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(h.repository.completionWrites, 1);
        h.dispose();
      });
    },
  );
  test(
    'same-layout programmatic jump cannot turn a middle navigation into an end visit',
    () {
      fakeAsync((clock) {
        final h = _Harness()..repository.positions['a'] = _oldProgress(.1);
        unawaited(h.start());
        clock.flushMicrotasks();
        h.report([_sample(top: -300)], navigation: 1);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 300));
        clock.flushMicrotasks();
        h.report([_sample(top: -600)], navigation: 1);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 500));
        clock.flushMicrotasks();
        expect(h.repository.completed, isEmpty);
        expect(h.repository.positions['a']!.progressPercent, .5);
        h.report([_sample(top: -600)], navigation: 2);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(h.repository.completed, {'a'});
        h.dispose();
      });
    },
  );

  test(
    'image or font geometry reaching the end needs a fresh navigation proof',
    () {
      fakeAsync((clock) {
        final h = _Harness()..repository.positions['a'] = _oldProgress(.1);
        unawaited(h.start());
        clock.flushMicrotasks();
        h.report([_sample(top: -300)], navigation: 1);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 300));
        clock.flushMicrotasks();
        expect(h.repository.completed, isEmpty);
        h.report([
          _sample(top: -300, height: 900, geometry: 'font-or-image-layout'),
        ], navigation: 1);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 500));
        clock.flushMicrotasks();
        expect(h.repository.completed, isEmpty);
        expect(h.repository.positions['a']!.progressPercent, .5);
        h.report([
          _sample(top: -300, height: 900, geometry: 'font-or-image-layout'),
        ], navigation: 2);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(h.repository.completed, {'a'});
        h.dispose();
      });
    },
  );
}

NovelReadingProgress _oldProgress(
  double fraction, {
  bool? valid = true,
  String basis = NovelProgressPercentBasis.pagedStartV1,
}) => NovelReadingProgress(
  novelId: 'novel',
  episodeId: 'a',
  scrollOffset: 900,
  updatedAt: DateTime(2026),
  flowMode: NovelReaderFlowMode.pagedLtr,
  pageIndex: 4,
  pageCount: 10,
  anchorNodeId: 'old-node',
  anchorTextOffset: -12,
  anchorFormatVersion: 91,
  anchorTextIdentity: 'future',
  paginationKey: 'old-layout',
  progressPercent: fraction,
  isProgressPercentValid: valid,
  percentBasis: basis,
);

ThreadBodyReadingSample _sample({
  String pid = '101',
  Object identity = 'body-a',
  double top = 0,
  double height = 1200,
  double extent = 600,
  bool ready = true,
  bool finalBoundary = true,
  Object geometry = 'layout-a',
}) => ThreadBodyReadingSample(
  tid: '100',
  pid: pid,
  bodyIdentity: identity,
  relativeBodyTop: top,
  bodyHeight: height,
  effectiveViewportHeight: 600,
  visibleExtent: extent,
  bodyReady: ready,
  finalBoundaryKnown: finalBoundary,
  geometryIdentity: geometry,
);

final class _Harness {
  _Harness({NovelReadingSessionEntry entry = NovelReadingSessionEntry.resume}) {
    committer = DefaultNovelReaderProgressCommitter(repository: repository);
    adapter = NovelSourceReadingAdapter(
      context: NovelSourceReadingContext(
        novelId: 'novel',
        chapters: [_a, _b],
        initialEpisodeId: 'a',
        entry: entry,
      ),
      readingStateRepository: repository,
      committer: committer,
      mutationBarrier: barrier,
      onCommitted: () => notifications++,
    );
  }
  final repository = _Repository();
  final barrier = NovelReadingMutationBarrier();
  late final DefaultNovelReaderProgressCommitter committer;
  late final NovelSourceReadingAdapter adapter;
  int notifications = 0;
  Future<void> start() async {
    await adapter.prepare();
    adapter.onContentChanged('page');
    adapter.onVisibility(frontmost: true, resumed: true);
  }

  ThreadBodyRestoreTarget? restore() =>
      adapter.restoreTarget(tid: '100', pid: '101', bodyIdentity: 'body-a');
  void report(
    List<ThreadBodyReadingSample> samples, {
    int navigation = 0,
    bool idle = true,
    Object content = 'page',
  }) => adapter.onViewport(
    ThreadBodyReadingViewport(
      contentIdentity: content,
      tid: '100',
      page: 1,
      samples: samples,
      idle: idle,
      restoreSettled: true,
      userNavigationRevision: navigation,
    ),
  );
  void dispose() {
    adapter.dispose();
    committer.cancel();
  }
}

final class _Repository extends Fake
    implements NovelRepository, NovelReadingStateRepository {
  final Map<String, NovelReadingProgress> positions = {};
  final Set<String> completed = {};
  String? recent;
  bool failLoad = false;
  bool failWrite = false;
  int loads = 0;
  int writes = 0;
  int completionWrites = 0;
  Future<void> Function(NovelReadingProgress, bool)? beforeWrite;
  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async {
    loads++;
    if (failLoad) throw StateError('load failed');
    return NovelReadingStateSnapshot(
      novelId: novelId,
      progressByEpisode: positions,
      recentEpisodeId: recent,
      episodeStates: {
        for (final episode in completed)
          episode: LibraryEpisodeState(
            moduleKey: LibraryModuleKey.novel,
            workId: novelId,
            episodeId: episode,
            isRead: true,
            isBookmarked: false,
            isDownloaded: false,
          ),
      },
    );
  }

  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) async => positions[episodeId];
  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false) return false;
    await beforeWrite?.call(progress, markCompleted);
    if (failWrite) throw StateError('write failed');
    if (canCommit?.call() == false) return false;
    positions[progress.episodeId] = progress;
    recent = progress.episodeId;
    writes++;
    if (markCompleted) {
      completed.add(progress.episodeId);
      completionWrites++;
    }
    return true;
  }

  @override
  Future<bool> resetChapter({
    required String novelId,
    required String episodeId,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false) return false;
    positions.remove(episodeId);
    completed.remove(episodeId);
    return true;
  }

  @override
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false) return false;
    if (isRead) {
      completed.add(episodeId);
    } else {
      positions.remove(episodeId);
      completed.remove(episodeId);
    }
    return true;
  }
}
