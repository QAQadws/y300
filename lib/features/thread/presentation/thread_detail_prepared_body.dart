import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// A page retains pure display values after individual lazy chunks unmount.
final class ThreadDetailPreparedBody {
  const ThreadDetailPreparedBody({
    required this.request,
    required this.document,
  });

  final ForumHtmlPreparationRequest request;
  final ForumHtmlPreparedRenderDocument document;

  int get retainedCodeUnits =>
      document.preparedHtml.length +
      (document.safeDisplayPlan?.chunks.fold<int>(
            0,
            (length, chunk) => length + chunk.html.length,
          ) ??
          0);
}

/// Admission is bounded without evicting a floor and changing its extent while
/// another floor is visible. Values retire when the page or input changes.
final class ThreadDetailPreparedBodyStore {
  ThreadDetailPreparedBodyStore({
    this.maxBodies = 4,
    this.maxRetainedCodeUnits = 2 * 1024 * 1024,
  });

  final int maxBodies;
  final int maxRetainedCodeUnits;
  final _bodies = <String, ThreadDetailPreparedBody>{};
  int _retainedCodeUnits = 0;

  Map<String, ThreadDetailPreparedBody> get bodies => Map.unmodifiable(_bodies);
  ThreadDetailPreparedBody? operator [](String pid) => _bodies[pid];
  int get retainedCodeUnits => _retainedCodeUnits;

  bool canAdmit(String pid, ThreadDetailPreparedBody body) {
    final previous = _bodies[pid];
    return body.document.safeDisplayPlan?.isChunked == true &&
        (_bodies.length < maxBodies || previous != null) &&
        _retainedCodeUnits -
                (previous?.retainedCodeUnits ?? 0) +
                body.retainedCodeUnits <=
            maxRetainedCodeUnits;
  }

  bool admit(String pid, ThreadDetailPreparedBody body) {
    if (!canAdmit(pid, body)) return false;
    _retainedCodeUnits -= _bodies[pid]?.retainedCodeUnits ?? 0;
    _bodies[pid] = body;
    _retainedCodeUnits += body.retainedCodeUnits;
    return true;
  }

  void retainWhere(bool Function(String, ThreadDetailPreparedBody) valid) {
    _bodies.removeWhere((pid, body) {
      if (valid(pid, body)) return false;
      _retainedCodeUnits -= body.retainedCodeUnits;
      return true;
    });
  }

  void clear() {
    _bodies.clear();
    _retainedCodeUnits = 0;
  }
}
