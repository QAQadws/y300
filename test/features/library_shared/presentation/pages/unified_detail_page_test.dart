import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';

void main() {
  testWidgets('UnifiedDetailPage renders header/chapter and FAB', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: _FakeDetailAdapter(),
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('测试作品'), findsWidgets);
    expect(find.byKey(const Key('unified-detail-author-row')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-author-row')),
        matching: find.byIcon(Icons.person_outlined),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('unified-detail-collapsed-title')),
        matching: find.byType(AnimatedOpacity),
      )),
      isA<AnimatedOpacity>().having((w) => w.opacity, 'opacity', 0),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('unified-detail-collapsed-title')),
        matching: find.byType(AnimatedOpacity),
      )),
      isA<AnimatedOpacity>().having((w) => w.opacity, 'opacity', 1),
    );

    // 章节列表位于下方 sliver，测试中需要滚动后再断言。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')), findsOneWidget);

    expect(find.text('继续'), findsOneWidget);
    expect(find.byIcon(Icons.file_download), findsOneWidget);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
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
      author: '作者A',
      inShelf: true,
      intro: '这是一段简介',
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

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return const [];
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

