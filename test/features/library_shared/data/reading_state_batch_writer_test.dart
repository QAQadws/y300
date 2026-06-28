import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/services/reading_state_batch_writer_impl.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  test('setWorkRead delegates collection write and emits single-work refresh', () async {
    final stateRepository = _RecordingLibraryStateRepository();
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final writer = DefaultReadingStateBatchWriter(
      stateRepository: stateRepository,
      shelfRefreshBus: bus,
    );

    await writer.setWorkRead(
      module: LibraryModuleKey.comic,
      workId: ' comic:1 ',
      isRead: false,
    );

    expect(stateRepository.calls, hasLength(1));
    expect(stateRepository.calls.single.moduleKey, LibraryModuleKey.comic);
    expect(stateRepository.calls.single.workIds, <String>{'comic:1'});
    expect(stateRepository.calls.single.isRead, isFalse);
    expect(stateRepository.calls.single.readAt, isNull);
    final signal = bus.signal.value;
    expect(signal?.modules, <LibraryModuleKey>{LibraryModuleKey.comic});
    expect(signal?.source, LibraryMutationSource.readingStateBatch);
    expect(signal?.reason, 'work_mark_all_unread_completed');
    expect(signal?.workId, 'comic:1');
    expect(signal?.payload['workIdCount'], 1);
    expect(signal?.payload['isRead'], isFalse);
  });

  test('setWorksRead ignores empty normalized ids', () async {
    final stateRepository = _RecordingLibraryStateRepository();
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final writer = DefaultReadingStateBatchWriter(
      stateRepository: stateRepository,
      shelfRefreshBus: bus,
    );

    await writer.setWorksRead(
      module: LibraryModuleKey.novel,
      workIds: <String>{'', '   '},
      isRead: true,
    );

    expect(stateRepository.calls, isEmpty);
    expect(bus.signal.value, isNull);
  });

  test('setWorksRead emits multi-work read refresh payload', () async {
    final stateRepository = _RecordingLibraryStateRepository();
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final writer = DefaultReadingStateBatchWriter(
      stateRepository: stateRepository,
      shelfRefreshBus: bus,
    );

    await writer.setWorksRead(
      module: LibraryModuleKey.novel,
      workIds: <String>{'novel:1', ' novel:2 '},
      isRead: true,
    );

    expect(stateRepository.calls, hasLength(1));
    expect(stateRepository.calls.single.moduleKey, LibraryModuleKey.novel);
    expect(stateRepository.calls.single.workIds, <String>{'novel:1', 'novel:2'});
    expect(stateRepository.calls.single.isRead, isTrue);
    expect(stateRepository.calls.single.readAt, isNotNull);
    final signal = bus.signal.value;
    expect(signal?.modules, <LibraryModuleKey>{LibraryModuleKey.novel});
    expect(signal?.source, LibraryMutationSource.readingStateBatch);
    expect(signal?.reason, 'works_mark_all_read_completed');
    expect(signal?.workId, isNull);
    expect(signal?.payload, <String, Object?>{
      'workIdCount': 2,
      'isRead': true,
    });
  });
}

class _RecordingLibraryStateRepository implements LibraryStateRepository {
  final List<_SetWorksReadStateCall> calls = <_SetWorksReadStateCall>[];

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
  }) async {
    calls.add(
      _SetWorksReadStateCall(
        moduleKey: moduleKey,
        workIds: Set<String>.from(workIds),
        isRead: isRead,
        readAt: readAt,
      ),
    );
  }

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
  }) async {}

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

class _SetWorksReadStateCall {
  const _SetWorksReadStateCall({
    required this.moduleKey,
    required this.workIds,
    required this.isRead,
    required this.readAt,
  });

  final LibraryModuleKey moduleKey;
  final Set<String> workIds;
  final bool isRead;
  final DateTime? readAt;
}
