import 'package:flutter/material.dart';

/// 论坛系原生页面共用的下拉刷新外壳（版块帖子列表、帖子详情等）。
///
/// 存在的理由不是省掉一次 [RefreshIndicator] 构造，而是把「下拉刷新」真正需要
/// 的**两件事**收在同一个文件里：外壳本身，以及子滚动视图必须配套使用的
/// [scrollPhysics]。缺后者时手势会在短内容上静默失效，而这恰好是最需要手动刷新
/// 的场景（只有一楼的帖子、冷版块），所以把配对关系写在一处比在每个页面各写一遍
/// 更不容易漏。
class ForumPullToRefresh extends StatelessWidget {
  const ForumPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  /// 子滚动视图应使用的滚动物理。
  ///
  /// 默认物理的 `shouldAcceptUserOffset` 在「内容撑不满一屏」时直接拒绝拖拽
  /// （`pixels == 0 && minScrollExtent == maxScrollExtent`），下拉手势根本到不了
  /// [RefreshIndicator]。这里不指定 parent，`applyTo` 会把平台物理接在链尾，
  /// clamping / bouncing 的手感保持不变。
  static const ScrollPhysics scrollPhysics = AlwaysScrollableScrollPhysics();

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
