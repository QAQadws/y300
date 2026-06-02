import 'package:y300/features/thread/domain/thread_content_classifier.dart';

// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 把「收藏帖 tid ⇄ 作品 workId」这一隐式关系显式化为一个领域查询服务。
// 取消收藏以 tid 为键（删除 API `op=delete&type=thread&id=<tid>`），
// favid 仅作辅助元数据，不参与删除逻辑。
//
// 实现落在阶段 1，基于现有 `favorite_threads` 表查询（不改 schema）。

/// 一个收藏帖在关联模型中的最小引用。
class FavoriteThreadRef {
  const FavoriteThreadRef({
    required this.tid,
    this.favid,
    this.categoryId,
  });

  /// 取消收藏的唯一键。
  final String tid;

  /// 收藏列表辅助元数据；删除逻辑不依赖它。
  final String? favid;

  /// 该收藏帖当前所属的收藏分类（可空）。
  final String? categoryId;
}

/// 一个作品（workId）当前关联的所有收藏来源。
///
/// 合并机制会把多个收藏帖（多个 tid）重指向同一个 workId，因此
/// 一个作品可能对应多条 [threads]。
class FavoriteWorkLinks {
  const FavoriteWorkLinks({
    required this.workId,
    required this.kind,
    required this.threads,
  });

  final String workId;
  final ThreadContentKind kind;
  final List<FavoriteThreadRef> threads;

  /// 是否还有未取消的收藏帖。取消整部作品后据此决定是否清除作品。
  bool get hasActiveThread => threads.isNotEmpty;

  /// 全部关联收藏帖的 tid（取消整部作品时逐个删除）。
  List<String> get tids =>
      threads.map((thread) => thread.tid).toList(growable: false);

  static const FavoriteWorkLinks empty = FavoriteWorkLinks(
    workId: '',
    kind: ThreadContentKind.unknown,
    threads: <FavoriteThreadRef>[],
  );
}

/// 收藏帖 tid ⇄ 作品 workId 的双向关联查询。
///
/// 设计原则：把跨页一致性所需的关联事实集中在一个领域服务，UI / 用例
/// 只依赖这个抽象，不直接拼 favorite_threads 的 SQL。
abstract class FavoriteLinkService {
  /// 作品 → 全部关联收藏帖（用于「取消整部作品」，逐个 tid 删除）。
  Future<FavoriteWorkLinks> linksForWork(String workId);

  /// 收藏帖 tid → 关联作品（用于「在收藏页取消单条」后判断作品是否还活着）。
  Future<String?> workIdForThread(String tid);

  /// 作品移除后是否已无任何活跃收藏来源 → 决定是否清除作品。
  Future<bool> hasAnyActiveThread(String workId);
}
