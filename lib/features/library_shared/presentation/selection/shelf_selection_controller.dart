import 'package:flutter/foundation.dart';

/// 书架多选状态机。
///
/// 这个控制器只关心是否处于多选态，以及哪些 workId 被选中，
/// 不负责任何批量业务动作。
class ShelfSelectionController extends ChangeNotifier {
  final Set<String> _selected = <String>{};
  bool _isSelecting = false;

  bool get isSelecting => _isSelecting;

  int get selectedCount => _selected.length;

  Set<String> get selectedWorkIds => Set<String>.unmodifiable(_selected);

  bool isSelected(String workId) => _selected.contains(workId);

  /// 长按进入多选，并选中第一项。
  void enter(String firstWorkId) {
    final added = _selected.add(firstWorkId);
    final startedSelecting = !_isSelecting;
    _isSelecting = true;
    if (added || startedSelecting) {
      notifyListeners();
    }
  }

  /// 切换单项选中状态。
  void toggle(String workId) {
    if (_selected.contains(workId)) {
      _selected.remove(workId);
    } else {
      _selected.add(workId);
    }
    if (!_isSelecting) {
      _isSelecting = true;
    }
    notifyListeners();
  }

  /// 全选当前可见集合。
  void selectAll(Iterable<String> all) {
    final before = _selected.length;
    _selected.addAll(all);
    if (_selected.length != before || !_isSelecting) {
      _isSelecting = true;
      notifyListeners();
    }
  }

  /// 反选当前可见集合。
  void invert(Iterable<String> all) {
    final next = <String>{
      for (final id in all)
        if (!_selected.contains(id)) id,
    };
    _selected
      ..clear()
      ..addAll(next);
    _isSelecting = true;
    notifyListeners();
  }

  /// 退出多选并清空选中。
  void exit() {
    if (!_isSelecting && _selected.isEmpty) {
      return;
    }
    _isSelecting = false;
    _selected.clear();
    notifyListeners();
  }
}
