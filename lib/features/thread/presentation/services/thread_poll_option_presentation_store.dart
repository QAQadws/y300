import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// Page-owned pure geometry and fold state. Option bodies still unmount and
/// release their renderer sessions when their floor leaves the list cache.
final class ThreadPollOptionPresentationStore {
  final _values =
      <
        ({String pid, String optionId}),
        ({String html, ForumHtmlBodyPresentation presentation})
      >{};

  ForumHtmlBodyPresentation obtain(String pid, String optionId, String html) {
    final key = (pid: pid, optionId: optionId);
    final previous = _values[key];
    if (previous != null && previous.html == html) return previous.presentation;
    previous?.presentation.dispose();
    final presentation = ForumHtmlBodyPresentation();
    _values[key] = (html: html, presentation: presentation);
    return presentation;
  }

  void retainSources(Map<String, Map<String, String>> sources) {
    _values.removeWhere((key, value) {
      if (sources[key.pid]?[key.optionId] == value.html) return false;
      value.presentation.dispose();
      return true;
    });
  }

  void clear() {
    for (final value in _values.values) {
      value.presentation.dispose();
    }
    _values.clear();
  }
}
