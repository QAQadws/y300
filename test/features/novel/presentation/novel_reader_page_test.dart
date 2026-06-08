import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

void main() {
  testWidgets('NovelReaderPage shows immersive menu from center tap', (
    tester,
  ) async {
    await tester.pumpWidget(_buildReaderApp(repository: _FakeNovelRepository()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-episode-selector')), findsNothing);

    var topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isTrue);

    await _showReaderMenu(tester);

    topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isFalse);
    expect(find.text('测试小说'), findsOneWidget);
    expect(find.text('第1章'), findsOneWidget);
  });

  testWidgets('NovelReaderPage hides menu after content scroll', (tester) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);

    var topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isFalse);

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -180),
    );
    await tester.pump();

    topGate = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(topGate.ignoring, isTrue);
  });

  testWidgets('NovelReaderPage opens catalog and switches chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-catalog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-list-sheet')), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')));
    await tester.pumpAndSettle();

    expect(find.text('第三段。'), findsOneWidget);
    expect(find.text('第一段。'), findsNothing);
    expect(repository.savedProgressEpisodeIds, contains('novel:49:100:5001'));
  });

  testWidgets('NovelReaderPage display sheet persists style changes', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-display')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-theme-sepia')), findsOneWidget);

    await tester.tap(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();

    expect(repository.latestPreferences?.themeMode, 'sepia');
  });

  testWidgets('NovelReaderPage open thread uses novel detail source tid', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(),
        threadRepository: _FakeThreadRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-top-action-open-thread')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets('NovelReaderPage back button saves progress before pop', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(30, (index) => '第一章段落 $index'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [
            novelRepositoryProvider.overrideWithValue(repository),
            novelDownloadServiceProvider.overrideWithValue(_NoopNovelDownloadService()),
          ],
          child: const NovelReaderPage(
            novelId: 'novel:49:100',
            initialEpisodeId: 'novel:49:100:5001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('novel-reader-paragraph-list')),
      const Offset(0, -220),
    );
    await tester.pump();
    await _showReaderMenu(tester);

    await tester.tap(find.byKey(const Key('shared-reader-top-back-button')));
    await tester.pumpAndSettle();

    expect(repository.lastSavedOffset, greaterThan(0));
  });

  testWidgets('NovelReaderPage prefers downloaded chapter json', (tester) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(),
        downloadService: _DownloadedNovelServiceFake(
          const NovelChapterContent(
            episodeId: 'novel:49:100:5001',
            rawHtml: '<p>离线段。</p>',
            plainText: '离线段。',
            paragraphs: <String>['离线段。'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('离线段。'), findsOneWidget);
    expect(find.text('第一段。'), findsNothing);
  });
}

Future<void> _showReaderMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 300));
  await tester.pump(const Duration(milliseconds: 330));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

Widget _buildReaderApp({
  required _FakeNovelRepository repository,
  NovelDownloadService? downloadService,
  ThreadRepository? threadRepository,
}) {
  return ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      novelDownloadServiceProvider.overrideWithValue(
        downloadService ?? _NoopNovelDownloadService(),
      ),
      if (threadRepository != null)
        threadRepositoryProvider.overrideWithValue(threadRepository),
    ],
    child: const MaterialApp(
      home: NovelReaderPage(
        novelId: 'novel:49:100',
        initialEpisodeId: 'novel:49:100:5001',
      ),
    ),
  );
}

class _FakeThreadRepository implements ThreadRepository {
  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
  }) async {
    return ApiSuccess(
      ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '测试小说',
        author: 'alice',
        replies: 0,
        views: 1,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      ),
    );
  }
}

class _NoopNovelDownloadService implements NovelDownloadService {
  @override
  Future<void> deleteChapterDownload({required String novelId, required String episodeId}) async {}

  @override
  Future<DownloadedNovelChapter> downloadChapter({required String novelId, required String episodeId}) {
    throw UnimplementedError();
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return null;
  }
}

class _DownloadedNovelServiceFake extends _NoopNovelDownloadService {
  _DownloadedNovelServiceFake(this.content);

  final NovelChapterContent content;

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return content.episodeId == episodeId ? content : null;
  }
}

class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository({
    List<String>? firstParagraphs,
  }) : firstParagraphs = firstParagraphs ?? const <String>['第一段。', '第二段。'];

  final List<String> firstParagraphs;
  NovelReaderPreferences preferences = NovelReaderPreferences.defaults();
  NovelReaderPreferences? latestPreferences;
  double lastSavedOffset = 0;
  final savedProgressEpisodeIds = <String>[];

  @override
  Future<String> createCategory({required String name}) async => 'default';

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
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 2,
    );
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    if (episodeId == 'novel:49:100:5002') {
      return const NovelChapterContent(
        episodeId: 'novel:49:100:5002',
        rawHtml: '<p>第三段。</p><p>第四段。</p>',
        plainText: '第三段。\n第四段。',
        paragraphs: <String>['第三段。', '第四段。'],
      );
    }
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: '<p>第一段。</p><p>第二段。</p>',
      plainText: firstParagraphs.join('\n'),
      paragraphs: firstParagraphs,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    const episodes = <NovelEpisodeItem>[
      NovelEpisodeItem(
        episodeId: 'novel:49:100:5001',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5001',
        sourcePage: 1,
        episodeTitle: '第1章',
        orderIndex: 0,
        datelineText: '2026-05-03',
      ),
      NovelEpisodeItem(
        episodeId: 'novel:49:100:5002',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5002',
        sourcePage: 1,
        episodeTitle: '第2章',
        orderIndex: 1,
        datelineText: '2026-05-04',
      ),
    ];
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => preferences;

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async =>
      const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    return null;
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 2);
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    lastSavedOffset = scrollOffset;
  }

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    latestPreferences = preferences;
    this.preferences = preferences;
  }
}
