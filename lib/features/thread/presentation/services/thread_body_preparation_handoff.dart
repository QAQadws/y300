import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import '../thread_detail_prepared_body.dart';

/// A new lease stays distinct even when its display identity returns A -> B -> A.
final class ThreadBodyPreparationLease {
  ThreadBodyPreparationLease._({required this.pid, required this.identity});

  final String pid;
  final Object identity;
}

enum ThreadBodyPreparationHandoffResult { retired, admitted, wholeFallback }

/// Owns only pure admission values. Frames and Context stay in the page; a late
/// completion can release or replace only its own current lease.
final class ThreadBodyPreparationHandoff {
  ThreadBodyPreparationHandoff(this.store);

  final ThreadDetailPreparedBodyStore store;
  final _pending = <String, ThreadBodyPreparationLease>{};
  final _declined = <String, Object>{};

  // Cache capacity controls reusable values, never a floor's display structure.
  // Preserve the original capability and any explicit caller-specific policy.
  ForumHtmlRenderPreparer selectPreparer(ForumHtmlPreparationRequest request) =>
      request.preparer;

  ThreadBodyPreparationLease? pendingFor(String pid) => _pending[pid];

  /// Release a declined source identity before querying the current input.
  void retireDeclinedInput(String pid, Object currentIdentity) {
    if (_declined[pid] != currentIdentity) _declined.remove(pid);
  }

  bool isDeclined(String pid, Object identity) => _declined[pid] == identity;
  bool isCurrent(ThreadBodyPreparationLease lease) =>
      identical(_pending[lease.pid], lease);

  bool canReserve(String pid, ThreadDetailPreparedBody candidate) =>
      store.canAdmit(pid, candidate);

  ThreadBodyPreparationLease begin({
    required String pid,
    required Object identity,
  }) {
    final lease = ThreadBodyPreparationLease._(pid: pid, identity: identity);
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
    // An input that no longer supports safe structure restores the whole-body
    // path. Cache eviction alone never calls this method.
    store.retainWhere((pid, _) => pid != lease.pid);
  }

  ThreadBodyPreparationHandoffResult complete(
    ThreadBodyPreparationLease lease,
    ThreadDetailPreparedBody body, {
    required bool currentInput,
    int seedOrdinal = 0,
  }) {
    if (!isCurrent(lease)) return ThreadBodyPreparationHandoffResult.retired;
    if (!currentInput) {
      release(lease);
      return ThreadBodyPreparationHandoffResult.retired;
    }
    if (!canReserve(lease.pid, body) ||
        !store.admit(lease.pid, body, seedOrdinal: seedOrdinal)) {
      final previous = store[lease.pid];
      if (previous != null && previous.identity == body.request.identity) {
        // The same input must not change already published boundaries because
        // a later preparation produced inconsistent output.
        release(lease);
        return ThreadBodyPreparationHandoffResult.retired;
      }
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
  }

  void retainPids(Set<String> activePids) {
    _pending.removeWhere((pid, _) => !activePids.contains(pid));
    _declined.removeWhere((pid, _) => !activePids.contains(pid));
  }
}
