/// In-memory evidence only for overlapping rounds. Durable foreground requests
/// live in the job repository; after restart there is no old round to protect.
class FavoriteMembershipTracker {
  int revision = 0;
  final Map<(Object?, String), ({int revision, bool favorited, String? id})>
  _changes = {};

  int versionFor(Object? owner, String tid) =>
      _changes[(owner, tid)]?.revision ?? 0;
  bool isUnfavorited(Object? owner, String tid) =>
      _changes[(owner, tid)]?.favorited == false;
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
      if (old != null && old.favorited == favorited && old.id == id) continue;
      _changes[(owner, tid)] = (
        revision: ++revision,
        favorited: favorited,
        id: id,
      );
    }
  }

  bool changedSince(Object? owner, String tid, int since) =>
      versionFor(owner, tid) > since;
}
