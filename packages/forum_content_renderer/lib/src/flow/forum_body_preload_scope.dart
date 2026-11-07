import 'package:flutter/foundation.dart';

/// One owner's optional display work yields while any visible view is missing
/// resources. This carries demand only; scheduling and leases stay in views.
final class ForumBodyPreloadScope extends ChangeNotifier {
  final _visible = <Object>{};
  bool _paused = false, _closed = false;

  bool get mayPreload => !_closed && !_paused && _visible.isEmpty;

  void setVisibleWork(Object consumer, bool pending) {
    if (_closed) return;
    final before = mayPreload;
    if (pending) {
      _visible.add(consumer);
    } else {
      _visible.remove(consumer);
    }
    if (before != mayPreload) notifyListeners();
  }

  /// A later viewport move may resume optional work after memory pressure.
  void pause() => _setPaused(true);
  void resume() => _setPaused(false);

  void _setPaused(bool value) {
    if (_closed || _paused == value) return;
    _paused = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _visible.clear();
    super.dispose();
  }
}
