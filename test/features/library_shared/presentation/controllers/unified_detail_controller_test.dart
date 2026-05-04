import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_detail_controller.dart';

void main() {
  test('initialize loads header and chapters', () async {
    final controller = UnifiedDetailController(
      adapter: _FakeDetailAdapter(),
      workId: 'work-1',
    );

    await controller.initialize();

    expect(controller.state.header?.title, '测试作品');
    expect(controller.state.chapters.length, 1);
    expect(controller.state.isLoading, isFalse);
  });

  test('toggleSortDirection switches chapter order direction', () async {
    final adapter = _FakeDetailAdapter();
    final controller = UnifiedDetailController(
      adapter: adapter,
      workId: 'work-1',
    );

    await controller.initialize();
    final before = controller.state.chapterSortOption.direction;
    await controller.toggleSortDirection();
    final after = controller.state.chapterSortOption.direction;

    expect(before == after, isFalse);
  });
}

class _FakeDetailAdapter implements DetailModuleAdapter {
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
    return const ThreadRouteTarget(tid: '100');
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
        workId: 'work-1',
        title: '第1章',
        orderIndex: 1,
      ),
    ];
  }

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    return const LibraryDetailHeader(
      workId: 'work-1',
      title: '测试作品',
      inShelf: true,
    );
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
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<void> refreshWork({required String workId}) async {}

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}
}

