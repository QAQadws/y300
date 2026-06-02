import 'package:flutter/foundation.dart';

/// 书架多选状态机（模块无关，纯 presentation 状态，无 I/O）。
///
/// 设计原则：
/// 1. 与数据查询正交 —— 不持有 `UnifiedShelfController` 的任何字段，
///    由页面同时组合两者，便于独立单测。
/// 2. 只描述「选了哪些 workId / 是否在多选态」，不知道任何业务动作。
///    具体能执行什么由 `ShelfSelectionActionAdapter` 决定。
///
/// workId 语义随模块：漫画/小说为作品 id，收藏页为 `favorite:tid`。
/// 控制器对其内容无感知，只当作不透明字符串集合处理。
class ShelfSelectionController extends ChangeNotifier {
  final Set<String> _selected = <String>{};
  bool _isSelecting = false;

  bool get isSelecting => _isSelecting;

  int get selectedCount => _selected.length;

  /// 当前选中集合的只读视图。
  Set<String> get selectedWorkIds => Set<String>.unmodifiable(_selected);

  bool isSelected(String workId) => _selected.contains(workId);

  /// 长按进入多选并选中第一项。重复进入只追加选中项。
  void enter(String firstWorkId) {
    // 必须先无条件加入选中项：用 `||` 短路会在首次进入时跳过 add，
    // 导致第一项永远没被选中。
    final added = _selected.add(firstWorkId);
    final startedSelecting = !_isSelecting;
    _isSelecting = true;
    if (added || startedSelecting) {
      notifyListeners();
    }
  }

  /// 点选 / 取消单项。多选态下取消到 0 项不自动退出，交由 UI 决定。
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

  /// 反选：在 [all] 范围内，保留未选中、清掉已选中（即「除选中外全选」）。
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

  /// 退出多选并清空选中（AppBar 左侧 X）。
  void exit() {
    if (!_isSelecting && _selected.isEmpty) {
      return;
    }
    _isSelecting = false;
    _selected.clear();
    notifyListeners();
  }
}
