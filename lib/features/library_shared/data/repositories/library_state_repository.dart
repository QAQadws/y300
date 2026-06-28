import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';

/// 统一状态仓储抽象。
///
/// 该仓储独立于 comic/novel 主仓储，避免“业务数据”和“跨模块状态”强耦合。
abstract class LibraryStateRepository {
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  });

  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  });

  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  });

  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  });

  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  });

  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  });

  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  });

  /// 批量写入一个或多个作品下全部章节的已读状态。
  ///
  /// 该接口面向持久化层，要求以集合式 upsert 保证“原本没有状态行的章节”
  /// 也能在一次事务内写入到统一状态表。
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) {
    throw UnimplementedError('setWorksReadState($moduleKey, $workIds, $isRead)');
  }

  /// 删除一个作品在 shared 状态表里的全部状态和标签绑定。
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) {
    throw UnimplementedError('purgeWorkState($moduleKey, $workId)');
  }

  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  });

  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  });

  Future<String> createTag({required String name});

  Future<List<LibraryTag>> getTags();

  Future<void> renameTag({
    required String tagId,
    required String newName,
  });

  Future<void> deleteTag({required String tagId});

  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  });

  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  });

  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  });

  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  });
}
