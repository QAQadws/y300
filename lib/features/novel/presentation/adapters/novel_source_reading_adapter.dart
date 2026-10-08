import 'dart:async';

import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/application/novel_reading_session_coordinator.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_body_geometry.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_reading_session.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';

/// Adapts explicitly bound native post bodies to the same chapter positions
/// used by the reader. It retains values and authority, never layout objects.
final class NovelSourceReadingAdapter
    implements ThreadBodyReadingObserver, ThreadBodyReadingSuspension {
  NovelSourceReadingAdapter({
    required this.context,
    required NovelReadingStateRepository readingStateRepository,
    required ScopedNovelReaderProgressCommitter committer,
    required NovelReadingMutationBarrier mutationBarrier,
    required void Function() onCommitted,
    NovelReadingSessionCoordinator? coordinator,
  }) : _repository = readingStateRepository,
       _committer = committer,
       _barrier = mutationBarrier,
       _onCommitted = onCommitted,
       _coordinator = coordinator ?? NovelReadingSessionCoordinator();

  final NovelSourceReadingContext context;
  final NovelReadingStateRepository _repository;
  final ScopedNovelReaderProgressCommitter _committer;
  final NovelReadingMutationBarrier _barrier;
  final void Function() _onCommitted;
  final NovelReadingSessionCoordinator _coordinator;
  final Map<String, NovelReadingProgress> _progress = {};
  Future<void>? _preparation;
  Future<void>? _draining;
  ThreadBodyReadingViewport? _pendingViewport;
  ThreadBodyReadingViewport? _pendingNavigationViewport;
  Object? _contentIdentity;
  Object? _activeBodyIdentity;
  Object? _navigationGeometryProof;
  bool? _initialWholeBodyVisible;
  NovelSourceReadingChapter? _activeChapter;
  NovelReaderProgressSnapshot? _confirmedSnapshot;
  bool _prepared = false;
  bool _retired = false;
  bool _frontmost = false;
  bool _resumed = false;
  bool _admissionPaused = false;
  bool _initialPreferenceConsumed = false;
  bool _initialEntryConsumed = false;
  bool _restoreIssued = false;
  int _contentGeneration = 0;
  int _admissionRevision = 0;
  int _barrierRevision = 0;
  int _navigationRevision = 0;
  int _highestObservedNavigationRevision = 0;

  Future<void> prepare() => _preparation ??= _prepare();

  Future<void> _prepare() async {
    final NovelReadingStateSnapshot state;
    try {
      state = await _repository.loadWorkState(novelId: context.novelId);
    } catch (_) {
      // Reading-state storage is optional to ordinary source browsing. A failed
      // batch must never be mistaken for a catalog with no recorded positions.
      retire();
      return;
    }
    if (_retired || state.novelId != context.novelId) return;
    _progress.addAll({
      for (final entry in state.progressByEpisode.entries)
        if (entry.value.novelId == context.novelId &&
            entry.value.episodeId == entry.key)
          entry.key: entry.value,
    });
    _prepared = true;
  }

  @override
  bool tracks(String tid, String pid) =>
      _prepared && !_retired && context.chapterForSource(tid, pid) != null;

  @override
  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  }) {
    if (!_prepared || _retired || _restoreIssued) return null;
    final chapter = context.chapterForSource(tid, pid);
    if (chapter == null || chapter != context.initialChapter) return null;
    _restoreIssued = true;
    final recorded = _progress[chapter.episodeId];
    final double? fraction;
    if (context.entry == NovelReadingSessionEntry.bodyEnd) {
      fraction = 1;
    } else if (context.entry == NovelReadingSessionEntry.explicitStart ||
        recorded == null) {
      fraction = 0;
    } else {
      final value = recorded.progressPercent;
      fraction =
          value.isFinite &&
              value >= 0 &&
              value <= 1 &&
              (recorded.isProgressPercentValid == true ||
                  (recorded.isProgressPercentValid == null && value > 0))
          ? value
          : null;
    }
    // Unrecognized provenance remains a read-only approximate restoration.
    // The thread has no evidence to reuse reader page numbers or text anchors.
    return fraction == null
        ? null
        : ThreadBodyRestoreTarget(
            fraction: fraction,
            requestIdentity: Object(),
          );
  }

  @override
  void onContentChanged(Object contentIdentity) {
    if (_retired || _contentIdentity == contentIdentity) return;
    _contentIdentity = contentIdentity;
    _contentGeneration++;
    _pendingViewport = null;
    _pendingNavigationViewport = null;
    _activeChapter = null;
    _activeBodyIdentity = null;
    _navigationGeometryProof = null;
    _initialWholeBodyVisible = null;
    _confirmedSnapshot = null;
    _coordinator.retire();
  }

  @override
  void onVisibility({required bool frontmost, required bool resumed}) {
    if (_retired) return;
    final paused = !frontmost || !resumed;
    if (_frontmost != frontmost ||
        _resumed != resumed ||
        _admissionPaused != paused) {
      _admissionRevision++;
    }
    _frontmost = frontmost;
    _resumed = resumed;
    _admissionPaused = paused;
    _coordinator.updateVisibility(frontmost: frontmost, resumed: resumed);
    if (!frontmost || !resumed) {
      _navigationRevision = _highestObservedNavigationRevision;
      _pendingViewport = null;
      _pendingNavigationViewport = null;
    }
  }

  @override
  void suspendForFlush() {
    if (_retired) return;
    // Stop queued viewport promotion synchronously, but retain the old confirmed
    // position's lease until the route has flushed it and revokes visibility.
    _admissionPaused = true;
    _admissionRevision++;
    _navigationRevision = _highestObservedNavigationRevision;
    _pendingViewport = null;
    _pendingNavigationViewport = null;
    cancelPendingCompletion();
  }

  @override
  void cancelPendingCompletion() {
    final token = _coordinator.session;
    if (token != null) _coordinator.cancelPendingCompletion(token);
  }

  @override
  void onViewport(ThreadBodyReadingViewport viewport) {
    if (!_accepts(viewport)) return;
    if (viewport.userNavigationRevision > _highestObservedNavigationRevision) {
      _highestObservedNavigationRevision = viewport.userNavigationRevision;
    }
    _pendingViewport = viewport;
    if (viewport.userNavigationRevision > _navigationRevision &&
        (_pendingNavigationViewport == null ||
            viewport.userNavigationRevision >
                _pendingNavigationViewport!.userNavigationRevision)) {
      // While an old chapter is flushing, preserve the first sample belonging
      // to this navigation. A same-revision image/layout compensation is not a
      // replacement position, even if it becomes the latest viewport facts.
      _pendingNavigationViewport = viewport;
    }
    _draining ??= _drain().catchError((Object _) {}).whenComplete(() {
      _draining = null;
      final pending = _pendingViewport;
      if (pending != null) onViewport(pending);
    });
  }

  bool _accepts(ThreadBodyReadingViewport viewport) =>
      _prepared &&
      !_retired &&
      _frontmost &&
      _resumed &&
      !_admissionPaused &&
      _contentIdentity == viewport.contentIdentity;

  Future<void> _drain() async {
    while (_pendingViewport != null && !_retired) {
      var viewport = _pendingViewport!;
      _pendingViewport = null;
      if (!_accepts(viewport)) continue;
      final admissionRevision = _admissionRevision;
      var sample = _selectBody(viewport);
      if (sample == null) {
        _navigationRevision = viewport.userNavigationRevision;
        _consumeNavigation();
        cancelPendingCompletion();
        continue;
      }
      var chapter = context.chapterForSource(sample.tid, sample.pid)!;
      if (_activeChapter?.episodeId != chapter.episodeId ||
          _activeBodyIdentity != sample.bodyIdentity) {
        final generation = _contentGeneration;
        // A fast drag can cross two chapters inside the debounce interval.
        // Flush the old confirmed body before retiring its producer lease.
        await _flushConfirmed();
        if (generation != _contentGeneration ||
            admissionRevision != _admissionRevision ||
            !_accepts(viewport)) {
          continue;
        }
        viewport = _pendingViewport ?? viewport;
        _pendingViewport = null;
        sample = _selectBody(viewport);
        if (sample == null) {
          _navigationRevision = viewport.userNavigationRevision;
          _consumeNavigation();
          cancelPendingCompletion();
          continue;
        }
        chapter = context.chapterForSource(sample.tid, sample.pid)!;
        _beginBody(chapter, sample.bodyIdentity);
      }
      _observe(viewport, sample, chapter);
    }
  }

  ThreadBodyReadingSample? _selectBody(ThreadBodyReadingViewport viewport) {
    final mapped = viewport.samples.where((sample) {
      return sample.tid.trim() == viewport.tid.trim() &&
          sample.visibleExtent.isFinite &&
          sample.visibleExtent > 0 &&
          sample.relativeBodyTop.isFinite &&
          sample.bodyHeight.isFinite &&
          sample.bodyHeight >= 0 &&
          sample.effectiveViewportHeight.isFinite &&
          sample.effectiveViewportHeight > 0 &&
          context.chapterForSource(sample.tid, sample.pid) != null;
    }).toList();
    if (mapped.isEmpty) return null;
    if (!_initialPreferenceConsumed) {
      final initial = context.initialChapter;
      for (final sample in mapped) {
        if (context.chapterForSource(sample.tid, sample.pid) == initial) {
          _initialPreferenceConsumed = true;
          return sample;
        }
      }
    }
    for (final sample in mapped) {
      if (sample.bodyIdentity == _activeBodyIdentity &&
          sample.relativeBodyTop <= 0 &&
          sample.relativeBodyTop + sample.bodyHeight > 0) {
        return sample;
      }
    }
    mapped.sort((a, b) => a.relativeBodyTop.compareTo(b.relativeBodyTop));
    return mapped.first;
  }

  void _beginBody(NovelSourceReadingChapter chapter, Object bodyIdentity) {
    _activeChapter = chapter;
    _activeBodyIdentity = bodyIdentity;
    _navigationGeometryProof = null;
    _initialWholeBodyVisible = null;
    _confirmedSnapshot = null;
    final isInitial =
        !_initialEntryConsumed && chapter.episodeId == context.initialEpisodeId;
    if (isInitial) _initialEntryConsumed = true;
    final recorded = _progress.containsKey(chapter.episodeId);
    final entry =
        isInitial &&
            (context.entry == NovelReadingSessionEntry.explicitStart ||
                context.entry == NovelReadingSessionEntry.bodyEnd ||
                context.entry == NovelReadingSessionEntry.readOnlyRestore)
        ? context.entry
        : recorded
        ? NovelReadingSessionEntry.resume
        : NovelReadingSessionEntry.firstStart;
    final token = _coordinator.begin(
      novelId: context.novelId,
      episodeId: chapter.episodeId,
      entry: entry,
    );
    _barrierRevision = _barrier.capture(context.novelId, chapter.episodeId);
    _coordinator.updateVisibility(frontmost: _frontmost, resumed: _resumed);
    _coordinator.updateReadiness(
      token,
      bodyReady: false,
      restoreSettled: false,
      readOnlyCompatibilityRestore:
          recorded && entry != NovelReadingSessionEntry.explicitStart,
    );
  }

  void _observe(
    ThreadBodyReadingViewport viewport,
    ThreadBodyReadingSample sample,
    NovelSourceReadingChapter chapter,
  ) {
    final token = _coordinator.session!;
    final navigation = _pendingNavigationViewport;
    ThreadBodyReadingSample? navigationSample;
    if (viewport.userNavigationRevision > _navigationRevision &&
        navigation?.userNavigationRevision == viewport.userNavigationRevision &&
        navigation!.restoreSettled) {
      for (final candidate in navigation.samples) {
        if (candidate.bodyIdentity == sample.bodyIdentity &&
            candidate.tid == sample.tid &&
            candidate.pid == sample.pid &&
            candidate.bodyReady &&
            candidate.visibleExtent > 0 &&
            _geometry(candidate).isUsable) {
          navigationSample = candidate;
          break;
        }
      }
    }
    _navigationRevision = viewport.userNavigationRevision;
    _consumeNavigation();
    _coordinator.updateReadiness(
      token,
      bodyReady: sample.bodyReady,
      restoreSettled: viewport.restoreSettled,
    );
    final geometry = _geometry(sample);
    final geometryIdentity = (sample.bodyIdentity, sample.geometryIdentity);
    _coordinator.updateGeometry(token, geometryIdentity);
    final fraction = geometry.progressPercent;
    if (sample.bodyReady && viewport.restoreSettled && fraction != null) {
      _initialWholeBodyVisible ??= geometry.wholeBodyVisible;
    }
    final confirmedNavigation =
        navigationSample != null && _coordinator.confirmNavigation(token);
    if (confirmedNavigation) {
      _navigationGeometryProof = _geometry(navigationSample).atBodyEnd
          ? (navigationSample.bodyIdentity, navigationSample.geometryIdentity)
          : null;
    }
    final firstPosition =
        _confirmedSnapshot == null &&
        (token.entry == NovelReadingSessionEntry.firstStart ||
            token.entry == NovelReadingSessionEntry.explicitStart);
    if (fraction != null &&
        sample.bodyReady &&
        viewport.restoreSettled &&
        (confirmedNavigation || firstPosition)) {
      // The first source position also retires a reader's queued old snapshot.
      // Passive restoration cannot claim that shared mutation authority.
      _barrier.invalidate(context.novelId, chapter.episodeId);
      _barrierRevision = _barrier.capture(context.novelId, chapter.episodeId);
      final snapshot = NovelReaderProgressSnapshot(
        novelId: context.novelId,
        episodeId: chapter.episodeId,
        flowMode: NovelReaderFlowMode.vertical,
        scrollOffset: 0,
        pageIndex: 0,
        progressPercent: confirmedNavigation
            ? _geometry(navigationSample).progressPercent ?? fraction
            : fraction,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
      );
      final lease = _coordinator.positionLease(
        token,
        positionIdentity: snapshot,
      );
      if (lease != null) {
        _confirmedSnapshot = snapshot;
        final guard = _guard(lease);
        _committer.scheduleScoped(
          snapshot,
          scope: (token, lease.revision),
          canCommit: guard,
          onCommitted: () {
            if (guard()) _didCommit(snapshot);
          },
        );
      }
    }
    final initialShortBody =
        _initialWholeBodyVisible == true &&
        geometry.wholeBodyVisible &&
        (token.entry == NovelReadingSessionEntry.firstStart ||
            token.entry == NovelReadingSessionEntry.explicitStart);
    // Unlike a stable position, chapter-end evidence belongs to the geometry
    // actually navigated. Image/font reflow cannot manufacture a new end visit.
    final hasEndAuthority =
        initialShortBody || _navigationGeometryProof == geometryIdentity;
    _coordinator.reportCompletion(
      token,
      bodyReady: sample.bodyReady,
      finalBoundaryKnown: sample.finalBoundaryKnown,
      atBodyEnd: hasEndAuthority && geometry.atBodyEnd,
      wholeBodyVisible: geometry.wholeBodyVisible,
      restoreSettled: viewport.restoreSettled,
      idle: viewport.idle,
      geometryIdentity: geometryIdentity,
      onComplete: (lease) => unawaited(_complete(lease)),
    );
  }

  void _consumeNavigation() {
    if ((_pendingNavigationViewport?.userNavigationRevision ?? -1) <=
        _navigationRevision) {
      _pendingNavigationViewport = null;
    }
  }

  NovelReadingBodyGeometry _geometry(ThreadBodyReadingSample sample) {
    // PID-centered lists can have negative document offsets. Translate both
    // origins together to use the existing body geometry without clamping.
    final origin = sample.relativeBodyTop < 0 ? sample.relativeBodyTop : 0.0;
    return NovelReadingBodyGeometry(
      bodyTop: sample.relativeBodyTop - origin,
      bodyHeight: sample.bodyHeight,
      viewportTop: -origin,
      effectiveViewportHeight: sample.effectiveViewportHeight,
      visibleBodyExtent: sample.visibleExtent,
      finalBoundaryKnown: sample.finalBoundaryKnown,
    );
  }

  bool Function() _guard(NovelReadingCommitLease lease) {
    final generation = _contentGeneration;
    final revision = _barrierRevision;
    return () =>
        !_retired &&
        generation == _contentGeneration &&
        lease.isValid &&
        _barrier.isCurrent(context.novelId, lease.token.episodeId, revision);
  }

  void _didCommit(NovelReaderProgressSnapshot snapshot) {
    _progress[snapshot.episodeId] = readingProgressFromSnapshot(snapshot);
    _onCommitted();
  }

  Future<void> _complete(NovelReadingCommitLease lease) async {
    final snapshot = _confirmedSnapshot;
    if (snapshot == null || snapshot.episodeId != lease.token.episodeId) {
      _coordinator.rejectCompletion(lease);
      return;
    }
    final guard = _guard(lease);
    try {
      final applied = await _repository.commitProgress(
        progress: readingProgressFromSnapshot(snapshot),
        markCompleted: true,
        canCommit: guard,
      );
      if (applied && guard()) {
        _didCommit(snapshot);
      } else {
        _coordinator.rejectCompletion(lease);
      }
    } catch (_) {
      _coordinator.rejectCompletion(lease);
    }
  }

  Future<void> _flushConfirmed() async {
    final snapshot = _confirmedSnapshot;
    final token = _coordinator.session;
    if (snapshot == null || token == null) return;
    final lease = _coordinator.positionLease(token, positionIdentity: snapshot);
    if (lease == null) return;
    final guard = _guard(lease);
    try {
      await _committer.flushScoped(
        snapshot,
        scope: (token, lease.revision),
        canCommit: guard,
        onCommitted: () {
          if (guard()) _didCommit(snapshot);
        },
      );
    } catch (_) {
      // Optional reading history must not block navigating the source thread.
    }
  }

  @override
  Future<void> flush() async {
    await _draining;
    await _flushConfirmed();
  }

  @override
  void retire() {
    if (_retired) return;
    _retired = true;
    _contentGeneration++;
    _pendingViewport = null;
    _pendingNavigationViewport = null;
    _confirmedSnapshot = null;
    _coordinator.dispose();
  }

  void dispose() => retire();
}
