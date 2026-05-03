import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';

/// 书架分页头通用策略，统一「业务分类 -> 头部 Tab」映射与选中索引计算。
///
/// 这样 comic/novel 只需提供最小分类模型，不需要在各自页面重复维护映射逻辑。
class ShelfPagerStrategy<T> {
  const ShelfPagerStrategy({
    required this.idOf,
    required this.labelOf,
  });

  final String Function(T item) idOf;
  final String Function(T item) labelOf;

  List<FixedSlotHeaderTab> buildTabs(List<T> items) {
    return items
        .map(
          (item) => FixedSlotHeaderTab(
            id: idOf(item),
            label: labelOf(item),
          ),
        )
        .toList(growable: false);
  }

  int resolveSelectedIndex({
    required List<FixedSlotHeaderTab> tabs,
    required String selectedId,
    int fallbackIndex = 0,
  }) {
    if (tabs.isEmpty) {
      return 0;
    }
    final index = tabs.indexWhere((tab) => tab.id == selectedId);
    if (index >= 0) {
      return index;
    }
    if (fallbackIndex < 0) {
      return 0;
    }
    if (fallbackIndex >= tabs.length) {
      return tabs.length - 1;
    }
    return fallbackIndex;
  }
}
