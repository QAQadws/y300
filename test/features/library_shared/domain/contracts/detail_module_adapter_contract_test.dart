import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

void main() {
  test('DetailModuleAdapter contract can be implemented by fake', () async {
    final adapter = _FakeDetailModuleAdapter();
    final header = await adapter.loadHeader(workId: 'w1');
    expect(header.workId, 'w1');

    final chapters = await adapter.loadChapters(
      workId: 'w1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    expect(chapters.length, 1);
  });
}

class _FakeDetailModuleAdapter implements DetailModuleAdapter {
  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<void> clearAllReadState({required String workId}) async {}

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {}

  @override
  Future<void> downloadAll({required String workId}) async {}

  @override
  Future<void> downloadUnread({required String workId}) async {}

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    return ReaderRouteTarget(workId: workId, episodeId: 'e1');
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({required String workId}) async {
    return const ThreadRouteTarget(tid: '1', subject: 's');
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    return const [
      LibraryChapterItem(
        episodeId: 'e1',
        workId: 'w1',
        title: '章节 1',
        orderIndex: 1,
      ),
    ];
  }

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    return LibraryDetailHeader(workId: workId, title: 'title', inShelf: true);
  }

  @override
  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {}

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) async {}

  @override
  Future<void> refreshWork({required String workId}) async {}

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return [
      LibraryCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<LibraryTag>> getWorkTags({required String workId}) async {
    return const [];
  }

  @override
  Future<List<LibraryTag>> getAllTags() async {
    return const [];
  }

  @override
  Future<void> addExistingTagToWork({
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> addNewTagToWork({
    required String workId,
    required String tagName,
  }) async {}

  @override
  Future<void> removeTagFromWork({
    required String workId,
    required String tagId,
  }) async {}
}
