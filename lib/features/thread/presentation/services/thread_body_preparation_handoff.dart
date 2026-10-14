import 'dart:math' as math;

import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import '../thread_detail_prepared_body.dart';

/// A new lease stays distinct even when its display identity returns A -> B -> A.
final class ThreadBodyPreparationLease {
  ThreadBodyPreparationLease._({
    required this.pid,
    required this.identity,
    required this.reservedCodeUnits,
  });

  final String pid;
  final Object identity;
  final int reservedCodeUnits;
}

enum ThreadBodyPreparationHandoffResult { retired, admitted, wholeFallback }

/// Owns only pure admission values. Frames and Context stay in the page; a late
/// completion can release or replace only its own current lease.
final class ThreadBodyPreparationHandoff {
  ThreadBodyPreparationHandoff(this.store);

  final ThreadDetailPreparedBodyStore store;
  final _pending = <String, ThreadBodyPreparationLease>{};
  final _declined = <String, Object>{};
  final _planningChoices =
      <String, ({Object inputIdentity, ForumHtmlRenderPreparer preparer})>{};

  /// Choose once per actual preparation input. Another floor consuming capacity
  /// must not flip a mounted consumer's preparer and repeat its preparation.
  ForumHtmlRenderPreparer selectPreparer(ForumHtmlPreparationRequest request) {
    final original = request.preparer;
    if (original is! DefaultForumHtmlRenderPreparer ||
        !original.supportsBackgroundPreparation ||
        !original.enableSafeDisplayPlanning) {
      return original;
    }
    final pid = request.sourceId;
    final inputIdentity = request.identity;
    final previous = _planningChoices[pid];
    if (previous?.inputIdentity == inputIdentity) return previous!.preparer;
    var count = store.bodies.length + (store[pid] == null ? 1 : 0);
    var occupied =
        store.retainedCodeUnits - (store[pid]?.retainedCodeUnits ?? 0);
    for (final lease in _pending.values) {
      if (lease.pid == pid) continue;
      final retained = store[lease.pid];
      if (retained == null) count++;
      occupied += math.max(
        0,
        lease.reservedCodeUnits - (retained?.retainedCodeUnits ?? 0),
      );
    }
    var available = math.max(0, store.maxRetainedCodeUnits - occupied);
    final originalBudget = original.safeDisplayPlanningCodeUnitBudget;
    if (originalBudget != null) available = math.min(available, originalBudget);
    final selected = DefaultForumHtmlRenderPreparer(
      enablePlainTextLinks: original.enablePlainTextLinks,
      enableSafeDisplayPlanning: count <= store.maxBodies && available > 0,
      safeDisplayPlanningCodeUnitBudget: available,
    );
    _planningChoices[pid] = (inputIdentity: inputIdentity, preparer: selected);
    return selected;
  }

  ThreadBodyPreparationLease? pendingFor(String pid) => _pending[pid];

  /// Release a declined source identity before querying the current input.
  void retireDeclinedInput(String pid, Object currentIdentity) {
    if (_declined[pid] != currentIdentity) _declined.remove(pid);
  }

  bool isDeclined(String pid, Object identity) => _declined[pid] == identity;
  bool isCurrent(ThreadBodyPreparationLease lease) =>
      identical(_pending[lease.pid], lease);

  bool canReserve(String pid, ThreadDetailPreparedBody candidate) {
    if (!store.canAdmit(pid, candidate)) return false;
    var count = store.bodies.length + (store[pid] == null ? 1 : 0);
    var units =
        store.retainedCodeUnits -
        (store[pid]?.retainedCodeUnits ?? 0) +
        candidate.retainedCodeUnits;
    for (final lease in _pending.values) {
      if (lease.pid == pid) continue;
      final previous = store[lease.pid];
      if (previous == null) count++;
      // A pending shrink cannot lend another floor budget until it commits.
      units += math.max(
        0,
        lease.reservedCodeUnits - (previous?.retainedCodeUnits ?? 0),
      );
    }
    return count <= store.maxBodies && units <= store.maxRetainedCodeUnits;
  }

  ThreadBodyPreparationLease begin({
    required String pid,
    required Object identity,
    required int reservedCodeUnits,
  }) {
    final lease = ThreadBodyPreparationLease._(
      pid: pid,
      identity: identity,
      reservedCodeUnits: reservedCodeUnits,
    );
    _pending[pid] = lease;
    return lease;
  }

  bool release(ThreadBodyPreparationLease lease) {
    if (!isCurrent(lease)) return false;
    _pending.remove(lease.pid);
    return true;
  }

  void decline(ThreadBodyPreparationLease lease) {
    if (!release(lease)) return;
    _declined[lease.pid] = lease.identity;
    // A stale chunk has no whole renderer of its own; remove it so the outer
    // entry planner can restore that floor's normal whole-body path.
    store.retainWhere((pid, _) => pid != lease.pid);
  }

  ThreadBodyPreparationHandoffResult complete(
    ThreadBodyPreparationLease lease,
    ThreadDetailPreparedBody body, {
    required bool currentInput,
  }) {
    if (!isCurrent(lease)) return ThreadBodyPreparationHandoffResult.retired;
    if (!currentInput) {
      release(lease);
      return ThreadBodyPreparationHandoffResult.retired;
    }
    if (!canReserve(lease.pid, body) || !store.admit(lease.pid, body)) {
      decline(lease);
      return ThreadBodyPreparationHandoffResult.wholeFallback;
    }
    _declined.remove(lease.pid);
    release(lease);
    return ThreadBodyPreparationHandoffResult.admitted;
  }

  void clear() {
    _pending.clear();
    _declined.clear();
    _planningChoices.clear();
  }

  void retainPids(Set<String> activePids) {
    _pending.removeWhere((pid, _) => !activePids.contains(pid));
    _declined.removeWhere((pid, _) => !activePids.contains(pid));
    _planningChoices.removeWhere((pid, _) => !activePids.contains(pid));
  }
}
