import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_management_sheet.dart';

void main() {
  testWidgets(
    'manages visibility, searches chapters, and removes manual ones',
    (tester) async {
      final adapter = _FakeManagementAdapter(
        chapters: [
          const DetailManagedChapter(
            episodeId: 'comic:100',
            title: '解析章节 100',
            sourceTid: '100',
            isManual: false,
            isHidden: false,
          ),
          const DetailManagedChapter(
            episodeId: 'comic:200',
            title: '手动章节 200',
            sourceTid: '200',
            isManual: true,
            isHidden: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedDetailChapterManagementSheet(
              workId: 'comic',
              adapter: adapter,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('解析章节 100'), findsOneWidget);
      expect(find.text('手动章节 200'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-management-remove-comic:100',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-management-remove-comic:200',
          ),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('unified-detail-chapter-management-search')),
        '200',
      );
      await tester.pump();
      expect(find.text('解析章节 100'), findsNothing);
      expect(find.text('手动章节 200'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-management-visibility-comic:200',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        adapter.chapters.singleWhere((item) => item.isManual).isHidden,
        isFalse,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-management-remove-comic:200',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('unified-detail-chapter-management-remove-confirm'),
        ),
      );
      await tester.pumpAndSettle();

      expect(adapter.removedEpisodeIds, contains('comic:200'));
      expect(find.text('手动章节 200'), findsNothing);
    },
  );
}

class _FakeManagementAdapter implements DetailChapterManagementAdapter {
  _FakeManagementAdapter({required List<DetailManagedChapter> chapters})
    : chapters = List<DetailManagedChapter>.from(chapters);

  final List<DetailManagedChapter> chapters;
  final List<String> removedEpisodeIds = <String>[];

  @override
  Future<List<DetailManagedChapter>> loadManagedChapters({
    required String workId,
  }) async => List<DetailManagedChapter>.from(chapters);

  @override
  Future<bool> addManualChapter({
    required String workId,
    required String input,
  }) async {
    chapters.add(
      DetailManagedChapter(
        episodeId: '$workId:$input',
        title: '章节 $input',
        sourceTid: input,
        isManual: true,
        isHidden: false,
      ),
    );
    return true;
  }

  @override
  Future<DetailChapterRemovalResult> removeManualChapter({
    required String workId,
    required String episodeId,
  }) async {
    final item = chapters.firstWhere(
      (chapter) => chapter.episodeId == episodeId,
    );
    if (!item.isManual) {
      return const DetailChapterRemovalResult(removed: false);
    }
    chapters.removeWhere((chapter) => chapter.episodeId == episodeId);
    removedEpisodeIds.add(episodeId);
    return const DetailChapterRemovalResult(removed: true);
  }

  @override
  Future<void> setChapterHidden({
    required String workId,
    required String episodeId,
    required bool isHidden,
  }) async {
    final index = chapters.indexWhere(
      (chapter) => chapter.episodeId == episodeId,
    );
    final item = chapters[index];
    chapters[index] = DetailManagedChapter(
      episodeId: item.episodeId,
      title: item.title,
      sourceTid: item.sourceTid,
      isManual: item.isManual,
      isHidden: isHidden,
    );
  }

  @override
  Future<void> setAllChaptersHidden({
    required String workId,
    required bool isHidden,
  }) async {
    for (var index = 0; index < chapters.length; index++) {
      final item = chapters[index];
      chapters[index] = DetailManagedChapter(
        episodeId: item.episodeId,
        title: item.title,
        sourceTid: item.sourceTid,
        isManual: item.isManual,
        isHidden: isHidden,
      );
    }
  }
}
