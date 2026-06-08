import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';

void main() {
  test('clearAllReadState delegates to ReadingStateBatchWriter when injected', () async {
    final writer = _RecordingReadingStateBatchWriter();
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      readingStateBatchWriter: writer,
      stateRepository: _RecordingLibraryStateRepository(),
    );

    await adapter.clearAllReadState(workId: 'novel:1');

    expect(writer.calls, hasLength(1));
    expect(writer.calls.single.module, LibraryModuleKey.novel);
    expect(writer.calls.single.workIds, <String>{'novel:1'});
    expect(writer.calls.single.isRead, isFalse);
  });

  test('clearAllReadState keeps fallback per-episode loop without writer', () async {
    final stateRepository = _RecordingLibraryStateRepository();
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      stateRepository: stateRepository,
    );

    await adapter.clearAllReadState(workId: 'novel:1');

    expect(stateRepository.unreadEpisodeIds, <String>[
      'novel:1:1',
      'novel:1:2',
    ]);
  });
}

class _FakeNovelRepository implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '75',
      title: 'Novel',
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 2,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return <NovelEpisodeItem>[
      NovelEpisodeItem(
        episodeId: '$novelId:1',
        novelId: novelId,
        sourceTid: '100',
        sourcePid: '1',
        episodeTitle: '第一章',
        orderIndex: 0,
      ),
      NovelEpisodeItem(
        episodeId: '$novelId:2',
        novelId: novelId,
        sourceTid: '100',
        sourcePid: '2',
        episodeTitle: '第二章',
        orderIndex: 1,
      ),
    ];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => NovelReaderPreferences.defaults();

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}

class _RecordingLibraryStateRepository implements LibraryStateRepository {
  final List<String> unreadEpisodeIds = <String>[];

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async => null;

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => null;

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => const <LibraryTag>[];

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => false;

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    if (isRead == false) {
      unreadEpisodeIds.add(episodeId);
    }
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}
}

class _RecordingReadingStateBatchWriter implements ReadingStateBatchWriter {
  final List<_ReadingStateBatchCall> calls = <_ReadingStateBatchCall>[];

  @override
  Future<void> setWorkRead({
    required LibraryModuleKey module,
    required String workId,
    required bool isRead,
  }) async {
    calls.add(
      _ReadingStateBatchCall(
        module: module,
        workIds: <String>{workId},
        isRead: isRead,
      ),
    );
  }

  @override
  Future<void> setWorksRead({
    required LibraryModuleKey module,
    required Set<String> workIds,
    required bool isRead,
  }) async {
    calls.add(
      _ReadingStateBatchCall(
        module: module,
        workIds: workIds,
        isRead: isRead,
      ),
    );
  }
}

class _ReadingStateBatchCall {
  const _ReadingStateBatchCall({
    required this.module,
    required this.workIds,
    required this.isRead,
  });

  final LibraryModuleKey module;
  final Set<String> workIds;
  final bool isRead;
}
