/// The visual landing point after a post has been located and verified.
enum ThreadPostLanding { top, bodyEnd }

/// A post identity and an optional, unverified ordinary-view page hint.
final class ThreadPostTarget {
  ThreadPostTarget({
    required String tid,
    required String pid,
    int? pageHint,
    this.landing = ThreadPostLanding.top,
  }) : tid = tid.trim(),
       pid = pid.trim(),
       pageHint = pageHint != null && pageHint > 0 ? pageHint : null;

  factory ThreadPostTarget.fromLink({
    required String tid,
    required String pid,
    required Uri sourceUri,
    int? pageHint,
    ThreadPostLanding landing = ThreadPostLanding.top,
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
      landing: landing,
    );
  }

  final String tid;
  final String pid;
  final int? pageHint;
  final ThreadPostLanding landing;

  bool get isValid =>
      RegExp(r'^[1-9]\d*$').hasMatch(tid) &&
      RegExp(r'^[1-9]\d*$').hasMatch(pid);

  @override
  bool operator ==(Object other) =>
      other is ThreadPostTarget &&
      tid == other.tid &&
      pid == other.pid &&
      pageHint == other.pageHint &&
      landing == other.landing;

  @override
  int get hashCode => Object.hash(tid, pid, pageHint, landing);
}
