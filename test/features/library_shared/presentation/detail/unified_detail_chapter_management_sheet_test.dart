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

  testWidgets('renames a parsed chapter and restores the source name', (
    tester,
  ) async {
    final adapter = _FakeManagementAdapter(
      chapters: [
        const DetailManagedChapter(
          episodeId: 'comic:100',
          title: '解析章节 100',
          sourceTitle: '解析章节 100',
          sourceTid: '100',
          isManual: false,
          isHidden: false,
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

    Future<void> rename(String text) async {
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-management-rename-comic:100',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          const Key('unified-detail-chapter-management-rename-input'),
        ),
        text,
      );
      await tester.tap(
        find.byKey(
          const Key('unified-detail-chapter-management-rename-confirm'),
        ),
      );
      await tester.pumpAndSettle();
    }

    await rename('我改的名字');
    expect(adapter.renamedTitles['comic:100'], '我改的名字');
    expect(find.text('我改的名字'), findsOneWidget);

    // 清空即还原：解析章节退回来源名，来源名本身没有被改名覆盖掉。
    await rename('   ');
    expect(adapter.renamedTitles['comic:100'], isNull);
    expect(find.text('解析章节 100'), findsOneWidget);
    expect(adapter.chapters.single.sourceTitle, '解析章节 100');
  });

  testWidgets('renaming a chapter back to its source name stores no override', (
    tester,
  ) async {
    final adapter = _FakeManagementAdapter(
      chapters: [
        const DetailManagedChapter(
          episodeId: 'comic:100',
          title: '我改的名字',
          sourceTitle: '解析章节 100',
          customTitle: '我改的名字',
          sourceTid: '100',
          isManual: false,
          isHidden: false,
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

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'unified-detail-chapter-management-rename-comic:100',
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 手动敲成与来源名一致，等价于“不要自定义名”：与「配置目录」同一套约定，
    // 否则来源以后改名了这一章会被旧名字钉住。
    await tester.enterText(
      find.byKey(const Key('unified-detail-chapter-management-rename-input')),
      '解析章节 100',
    );
    await tester.tap(
      find.byKey(const Key('unified-detail-chapter-management-rename-confirm')),
    );
    await tester.pumpAndSettle();

    expect(adapter.renamedTitles['comic:100'], isNull);
    expect(adapter.chapters.single.customTitle, isNull);
    expect(find.text('解析章节 100'), findsOneWidget);
  });

  testWidgets('renames a manual chapter and restores its default name', (
    tester,
  ) async {
    final adapter = _FakeManagementAdapter(
      chapters: [
        const DetailManagedChapter(
          episodeId: 'comic:200',
          title: '章节 200',
          sourceTitle: '章节 200',
          sourceTid: '200',
          isManual: true,
          isHidden: false,
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

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'unified-detail-chapter-management-rename-comic:200',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('unified-detail-chapter-management-rename-input')),
      '手动第一话',
    );
    await tester.tap(
      find.byKey(const Key('unified-detail-chapter-management-rename-confirm')),
    );
    await tester.pumpAndSettle();
    expect(find.text('手动第一话'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'unified-detail-chapter-management-rename-comic:200',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('unified-detail-chapter-management-rename-input')),
      '',
    );
    await tester.tap(
      find.byKey(const Key('unified-detail-chapter-management-rename-confirm')),
    );
    await tester.pumpAndSettle();

    expect(adapter.renamedTitles['comic:200'], isNull);
    expect(find.text('章节 200'), findsOneWidget);
  });
}

class _FakeManagementAdapter implements DetailChapterManagementAdapter {
  _FakeManagementAdapter({required List<DetailManagedChapter> chapters})
    : chapters = List<DetailManagedChapter>.from(chapters);

  final List<DetailManagedChapter> chapters;
  final List<String> removedEpisodeIds = <String>[];

  /// episodeId -> 传给 adapter 的自定义名；null 表示要求恢复来源名。
  final Map<String, String?> renamedTitles = <String, String?>{};

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
    chapters[index] = _copyWith(chapters[index], isHidden: isHidden);
  }

  @override
  Future<void> setAllChaptersHidden({
    required String workId,
    required bool isHidden,
  }) async {
    for (var index = 0; index < chapters.length; index++) {
      chapters[index] = _copyWith(chapters[index], isHidden: isHidden);
    }
  }

  @override
  Future<void> renameChapter({
    required String workId,
    required String episodeId,
    required String? customTitle,
  }) async {
    renamedTitles[episodeId] = customTitle;
    final index = chapters.indexWhere(
      (chapter) => chapter.episodeId == episodeId,
    );
    final item = chapters[index];
    // 复刻存储层的解析规则：自定义名优先，清空后回退来源名。面板重新读取时
    // 必须看到这套结果，测试才真的覆盖“清空即还原”。
    chapters[index] = DetailManagedChapter(
      episodeId: item.episodeId,
      title: customTitle ?? item.sourceTitle ?? '章节 ${item.sourceTid}',
      sourceTitle: item.sourceTitle,
      customTitle: customTitle,
      sourceTid: item.sourceTid,
      isManual: item.isManual,
      isHidden: item.isHidden,
    );
  }

  DetailManagedChapter _copyWith(
    DetailManagedChapter item, {
    required bool isHidden,
  }) {
    return DetailManagedChapter(
      episodeId: item.episodeId,
      title: item.title,
      sourceTitle: item.sourceTitle,
      customTitle: item.customTitle,
      sourceTid: item.sourceTid,
      isManual: item.isManual,
      isHidden: isHidden,
    );
  }
}
