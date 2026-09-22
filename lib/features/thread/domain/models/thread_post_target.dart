/// A post identity and an optional, unverified ordinary-view page hint.
final class ThreadPostTarget {
  ThreadPostTarget({required String tid, required String pid, int? pageHint})
    : tid = tid.trim(),
      pid = pid.trim(),
      pageHint = pageHint != null && pageHint > 0 ? pageHint : null;

  factory ThreadPostTarget.fromLink({
    required String tid,
    required String pid,
    required Uri sourceUri,
    int? pageHint,
  }) {
    // Page numbers belong to a view. Filtered/sorted links must be relocated
    // before opening the ordinary view, even if they contain a valid page.
    final changesView = const [
      'authorid',
      'ordertype',
      'viewpid',
      'ppp',
    ].any(sourceUri.queryParameters.containsKey);
    return ThreadPostTarget(
      tid: tid,
      pid: pid,
      pageHint: changesView ? null : pageHint,
    );
  }

  final String tid;
  final String pid;
  final int? pageHint;

  bool get isValid =>
      RegExp(r'^[1-9]\d*$').hasMatch(tid) &&
      RegExp(r'^[1-9]\d*$').hasMatch(pid);

  @override
  bool operator ==(Object other) =>
      other is ThreadPostTarget &&
      tid == other.tid &&
      pid == other.pid &&
      pageHint == other.pageHint;

  @override
  int get hashCode => Object.hash(tid, pid, pageHint);
}
