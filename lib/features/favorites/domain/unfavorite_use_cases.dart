import 'package:y300/features/thread/domain/thread_content_classifier.dart';

// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 取消收藏的两个对外用例签名：作品级（漫画/小说页）与单条级（收藏页）。
// 二者都以 tid 为删除键，编排「调用删除 API → 标记本地 removed →
// 若作品已无活跃收藏则清除作品 → 广播刷新」。
// 实现落在阶段 3，依赖阶段 1（删除 API + FavoriteLinkService）与
// 阶段 2（WorkPurgeService）。

/// 取消收藏的结构化结果。
///
/// 取消收藏可能逐个 tid 调用远端 API，部分成功部分失败必须可报告，
/// 不能假装整体成功（破坏性动作的可观测性要求）。
class UnfavoriteResult {
  const UnfavoriteResult({
    required this.requestedTids,
    required this.succeededTids,
    required this.failedTids,
    required this.purgedWorkIds,
  });

  /// 本次请求尝试取消的全部 tid。
  final List<String> requestedTids;

  /// 远端删除成功并已在本地标记 removed 的 tid。
  final List<String> succeededTids;

  /// 删除失败的 tid（保留收藏，不误删本地）。
  final List<String> failedTids;

  /// 因「已无活跃收藏」而触发清除程序的作品 workId。
  final List<String> purgedWorkIds;

  bool get hasFailure => failedTids.isNotEmpty;

  bool get allSucceeded => failedTids.isEmpty && succeededTids.isNotEmpty;
}

/// 作品级取消收藏（漫画/小说页多选）。
///
/// 取消一个作品 = 取消其全部关联收藏帖 tid；当作品再无活跃收藏来源时，
/// 走清除程序删除作品本地资源。
abstract class UnfavoriteWorkUseCase {
  Future<UnfavoriteResult> call({
    required String workId,
    required ThreadContentKind kind,
  });

  /// 多作品批量（多选场景）。逐作品执行并合并结果。
  Future<UnfavoriteResult> callMany({
    required Map<String, ThreadContentKind> workKinds,
  });
}

/// 单条收藏帖取消收藏（收藏页多选，选中项是 favorite:tid）。
///
/// 删除单个 tid；若该 tid 是其所属作品最后一个活跃收藏来源，则该作品
/// 也走清除程序。
abstract class UnfavoriteThreadUseCase {
  Future<UnfavoriteResult> call(String tid);

  /// 多条批量。
  Future<UnfavoriteResult> callMany(Set<String> tids);
}
