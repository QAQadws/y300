/// Runtime receipt evidence survives overlapping attempts until a validated
/// directory agrees. Durable foreground requests live in the job repository.
class FavoriteMembershipTracker {
  int revision = 0;
  final Map<
    (Object?, String),
    ({int revision, bool favorited, String? id, bool acknowledged})
  >
  _changes = {};

  int versionFor(Object? owner, String tid) =>
      _changes[(owner, tid)]?.revision ?? 0;
  bool isUnfavorited(Object? owner, String tid) {
    final change = _changes[(owner, tid)];
    return change?.favorited == false;
  }

  String? favoriteId(Object? owner, String tid) => _changes[(owner, tid)]?.id;

  void record(
    Object? owner,
    Set<String> tids, {
    required bool favorited,
    String? id,
    bool onlyIfUnknown = false,
  }) {
    for (final tid in tids) {
      final old = _changes[(owner, tid)];
      if (onlyIfUnknown && old != null) continue;
      if (old != null &&
          !old.acknowledged &&
          old.favorited == favorited &&
          old.id == id) {
        continue;
      }
      _changes[(owner, tid)] = (
        revision: ++revision,
        favorited: favorited,
        id: id,
        acknowledged: false,
      );
    }
  }

  bool changedSince(Object? owner, String tid, int since) =>
      versionFor(owner, tid) > since;

  bool hasUnacknowledged(Object? owner) => _changes.entries.any(
    (entry) => entry.key.$1 == owner && !entry.value.acknowledged,
  );

  bool blocksRemote(Object? owner, String tid, String? id, int since) {
    final change = _changes[(owner, tid)];
    return change != null &&
        (change.revision > since ||
            (!change.acknowledged &&
                (!change.favorited ||
                    (id != null && change.id != null && id != change.id))));
  }

  bool conflicts(Object? owner, Map<String, String?> remote) =>
      _changes.entries.any((entry) {
        if (entry.key.$1 != owner || entry.value.acknowledged) return false;
        final tid = entry.key.$2, change = entry.value;
        if (remote.containsKey(tid) != change.favorited) return true;
        final id = remote[tid];
        return change.favorited &&
            id != null &&
            change.id != null &&
            id != change.id;
      });

  void observeDirectory(
    Object? owner,
    int since,
    Map<String, String?> remote, {
    required bool complete,
  }) {
    for (final key in _changes.keys.toList()) {
      final change = _changes[key]!;
      if (key.$1 != owner || !change.acknowledged || change.revision > since) {
        continue;
      }
      final present = remote.containsKey(key.$2);
      if (!present && !complete) continue;
      // Confirming a removal does not release its tombstone to an old job.
      // Only a later validated directory can establish an external re-add.
      _changes[key] = (
        revision: change.revision,
        favorited: present,
        id: present
            ? remote[key.$2] ?? (change.favorited ? change.id : null)
            : null,
        acknowledged: true,
      );
    }
  }

  void acknowledge(Object? owner, int throughRevision) {
    for (final key in _changes.keys.toList()) {
      final change = _changes[key]!;
      if (key.$1 == owner && change.revision <= throughRevision) {
        _changes[key] = (
          revision: change.revision,
          favorited: change.favorited,
          id: change.id,
          acknowledged: true,
        );
      }
    }
  }
}
