import 'package:y300/features/library_shared/domain/models/library_models.dart';

// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 批量阅读状态写入：把「作品级 / 多作品级」的已读/未读标记收口到一个边界。
//
// 解耦目标：当前详情页 `clearAllReadState` 逐章 upsert、阅读器读完单章标记、
// 书架多选批量标记，三处语义分散。阶段 4 让它们共用本 writer，data 层用
// 集合式 upsert 事务从章节源表补齐状态行，避免大作品下 N 次 upsert 的卡顿、
// 中途不一致，以及“无状态行章节无法被批量标记”的问题。
//
// 角标联动：未读角标读的是同一张 library_episode_state 的 COUNT(is_read=0)，
// 写完后通过 LibraryShelfRefreshBus 广播即自动刷新，无需额外联动代码。

/// 作品级批量阅读状态写入。
abstract class ReadingStateBatchWriter {
  /// 把单个作品的所有章节标记为已读/未读（一次事务）。
  Future<void> setWorkRead({
    required LibraryModuleKey module,
    required String workId,
    required bool isRead,
  });

  /// 多作品批量（多选场景）。
  Future<void> setWorksRead({
    required LibraryModuleKey module,
    required Set<String> workIds,
    required bool isRead,
  });
}
