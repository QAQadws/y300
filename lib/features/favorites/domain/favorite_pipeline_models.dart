/// 收藏解析管道的处理级别。
///
/// 控制一条收藏记录在同步后被处理的深入程度：
/// - [bare]：仅基本元数据（title, tid, dateline）
/// - [light]：分类 + 轻量摄入，但不深度解析章节
/// - [full]：完全解析，含章节提取和封面处理
enum FavoriteProcessingLevel {
  bare,
  light,
  full,
}

/// 收藏管道中单条记录的处理阶段。
enum FavoriteItemProcessingState {
  /// 尚未进入管道
  pending,

  /// 正在加载帖子详情
  loadingDetail,

  /// 已分类（contentKind 已写入），尚未摄入模块
  classified,

  /// 正在摄入漫画/小说模块
  ingesting,

  /// 摄入完成，等待深度解析（封面/章节/搜索补全）
  awaitsDeepParse,

  /// 全部完成
  completed,

  /// 处理失败
  failed,
}

/// 收藏管道整体进度快照，供 UI 展示。
class FavoritePipelineProgress {
  const FavoritePipelineProgress({
    this.total = 0,
    this.classifiedCount = 0,
    this.ingestedCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.currentTid,
    this.message,
  });

  /// 需要处理的收藏总数
  final int total;

  /// 已完成快速分类的数量
  final int classifiedCount;

  /// 已摄入模块的数量
  final int ingestedCount;

  /// 完全完成的数量（含深度解析）
  final int completedCount;

  /// 处理失败的数量
  final int failedCount;

  /// 当前正在处理的帖子 tid
  final String? currentTid;

  /// 人类可读的进度描述
  final String? message;

  /// 快速分类完成度（0.0 ~ 1.0）
  double get classifyFraction =>
      total > 0 ? (classifiedCount / total).clamp(0.0, 1.0) : 0.0;

  /// 模块摄入完成度（0.0 ~ 1.0）
  double get ingestFraction =>
      total > 0 ? (ingestedCount / total).clamp(0.0, 1.0) : 0.0;

  bool get isActive => ingestedCount < total && total > 0;

  static const idle = FavoritePipelineProgress();
}
