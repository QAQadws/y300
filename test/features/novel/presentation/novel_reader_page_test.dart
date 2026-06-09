import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
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
    final subtitle = tester.widget<Text>(
      find.byKey(const Key('shared-reader-top-subtitle')),
    );
    expect(subtitle.data, '第1章');
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

  testWidgets('NovelReaderPage catalog searches chapters and shows empty state', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-catalog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-search-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('novel-reader-chapter-search-field')),
      '第3章',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5003')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5001')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('novel-reader-chapter-search-field')),
      '5002',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5002')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5003')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('novel-reader-chapter-search-field')),
      '不存在',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-search-empty')), findsOneWidget);
  });

  testWidgets('NovelReaderPage catalog marks last reading episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes(
      readingProgress: NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5003',
        scrollOffset: 120,
        updatedAt: DateTime(2026, 6, 1),
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-catalog')));
    await tester.pumpAndSettle();

    expect(find.text('上次阅读'), findsOneWidget);
  });

  testWidgets('NovelReaderPage catalog opens near current chapter', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.manyEpisodes(
      count: 20,
      currentIndex: 14,
    );
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        initialEpisodeId: 'novel:49:100:5015',
      ),
    );
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-catalog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5015')), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-chapter-novel:49:100:5001')), findsNothing);
  });

  testWidgets('NovelReaderPage bottom buttons and slider switch chapters', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    final previousButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-next-button')),
    );
    expect(previousButton.onPressed, isNull);
    expect(nextButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('shared-reader-next-button')));
    await tester.pumpAndSettle();

    expect(find.text('第三段。'), findsOneWidget);
    await _showReaderMenu(tester);
    final previousAfterSwitch = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    expect(previousAfterSwitch.onPressed, isNotNull);

    await tester.drag(
      find.byKey(const Key('shared-reader-progress-slider')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('第五段。'), findsOneWidget);
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
    expect(find.byKey(const Key('novel-reader-display-settings-sheet')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-flow-mode-control')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-content-width-slider')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-theme-sepia')));
    await tester.pumpAndSettle();

    expect(repository.latestPreferences?.themeMode, 'sepia');
    expect(repository.latestPreferences?.themePreset, NovelReaderThemePreset.sepia);
  });

  testWidgets('NovelReaderPage display sheet persists reading mode preference', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-display')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('分页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分页'));
    await tester.pumpAndSettle();

    expect(repository.latestPreferences?.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(find.byKey(const Key('novel-reader-paged-view')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsNothing);
  });

  testWidgets('NovelReaderPage renders paged mode and saves page index', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        18,
        (index) => '分页段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-paged-view')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsNothing);

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-next-button')));
    await tester.pumpAndSettle();

    expect(repository.readingProgress?.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(repository.readingProgress?.pageIndex, greaterThan(0));
  });

  testWidgets('NovelReaderPage restores saved paged page', (tester) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        18,
        (index) => '恢复分页段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
      readingProgress: NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        scrollOffset: 0,
        updatedAt: DateTime(2026, 6, 1),
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: 1,
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    final currentLabel = tester.widget<Text>(
      find.byKey(const Key('shared-reader-current-label')),
    );
    expect(currentLabel.data, '2');
  });

  testWidgets('NovelReaderPage right tap turns next page in paged LTR', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
      firstParagraphs: List<String>.generate(
        18,
        (index) => '右翻分页段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(720, 300));
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pumpAndSettle();
    expect(repository.readingProgress?.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(repository.readingProgress?.pageIndex, greaterThan(0));
  });

  testWidgets('NovelReaderPage left tap turns next page in paged RTL', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedRtl,
      ),
      firstParagraphs: List<String>.generate(
        18,
        (index) => '左翻分页段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(80, 300));
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pumpAndSettle();
    expect(repository.readingProgress?.flowMode, NovelReaderFlowMode.pagedRtl);
    expect(repository.readingProgress?.pageIndex, greaterThan(0));
  });

  testWidgets('NovelReaderPage vertical mode does not bind paged view', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: List<String>.generate(
        18,
        (index) => '滚动段落 $index ${List<String>.filled(70, '正文').join()}',
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-paragraph-list')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-paged-view')), findsNothing);

    await tester.tapAt(const Offset(720, 300));
    await tester.pumpAndSettle();

    expect(repository.readingProgress?.pageIndex ?? 0, 0);
  });

  testWidgets('NovelReaderPage constrains wide content column', (tester) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(contentMaxWidth: 360),
    );
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    final width = tester.getSize(find.byKey(const Key('novel-reader-content-column'))).width;

    expect(width, lessThanOrEqualTo(360));
  });

  testWidgets('NovelReaderPage can hide inline chapter title', (tester) async {
    final repository = _FakeNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(showChapterTitle: false),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-inline-chapter-title')), findsNothing);
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
            imageRequestHeaderBuilderProvider.overrideWithValue(
              const _StaticImageHeaderBuilder(),
            ),
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

  testWidgets('NovelReaderPage next chapter transition opens next episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-reader-next-chapter-transition')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('novel-reader-next-chapter-button')));
    await tester.pumpAndSettle();

    expect(find.text('第三段。'), findsOneWidget);
  });

  testWidgets('NovelReaderPage hides next chapter transition on last episode', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(
      _buildReaderApp(
        repository: repository,
        initialEpisodeId: 'novel:49:100:5003',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第五段。'), findsOneWidget);
    await _showReaderMenu(tester);
    final previousButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-prev-button')),
    );
    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('shared-reader-next-button')),
    );
    expect(previousButton.onPressed, isNotNull);
    expect(nextButton.onPressed, isNull);
    expect(
      find.byKey(const Key('novel-reader-next-chapter-transition')),
      findsNothing,
    );
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

  testWidgets('NovelReaderPage renders downloaded chapter html document', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(),
        downloadService: _DownloadedNovelServiceFake(
          const NovelChapterContent(
            episodeId: 'novel:49:100:5001',
            rawHtml: '''
<h2>离线标题</h2>
<blockquote>离线引用</blockquote>
<p>离线正文</p>
<img src="https://img.test/offline.jpg">
''',
            plainText: '离线标题\n离线引用\n离线正文',
            paragraphs: <String>['旧离线段'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('离线标题'), findsOneWidget);
    expect(find.text('离线引用'), findsOneWidget);
    expect(find.text('离线正文'), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-document-view')), findsOneWidget);
  });

  testWidgets('NovelReaderPage opens thread links from reader document', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildReaderApp(
        repository: _FakeNovelRepository(
          firstRawHtml:
              '<p><a href="forum.php?mod=viewthread&amp;tid=200">跳转原帖</a></p>',
          firstParagraphs: const <String>['跳转原帖'],
        ),
        threadRepository: _FakeThreadRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('novel-reader-link-block')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets('NovelReaderPage searches current chapter and highlights result', (
    tester,
  ) async {
    final repository = _FakeNovelRepository(
      firstParagraphs: const <String>['关键词在这里。', '关键词再次出现。'],
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-top-action-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-search-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('novel-reader-search-field')),
      '关键词',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-search-empty')), findsNothing);
    await tester.tap(
      find.byKey(
        const Key('novel-reader-search-result-novel:49:100:5001:node-1:0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-reader-search-sheet')), findsNothing);
    expect(find.textContaining('关键词在这里'), findsOneWidget);
  });

  testWidgets('NovelReaderPage toggles episode bookmark', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-top-action-bookmark')));
    await tester.pumpAndSettle();

    expect(
      repository.bookmarks.map((bookmark) => bookmark.bookmarkId),
      contains('episode-bookmark:novel:49:100:5001'),
    );
  });

  testWidgets('NovelReaderPage catalog shows bookmark badge', (
    tester,
  ) async {
    final repository = _FakeNovelRepository.threeEpisodes();
    repository.bookmarks.add(
      NovelReaderBookmark(
        bookmarkId: 'episode-bookmark:novel:49:100:5001',
        novelId: 'novel:49:100',
        episodeId: 'novel:49:100:5001',
        anchor: const NovelReaderTextAnchor(episodeId: 'novel:49:100:5001'),
        title: '第1章',
        snippet: '章节书签',
        createdAt: DateTime(2026, 6, 8),
        updatedAt: DateTime(2026, 6, 8),
      ),
    );
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-catalog')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('novel-reader-chapter-bookmark-novel:49:100:5001'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('NovelReaderPage adds and removes position bookmark', (
    tester,
  ) async {
    final repository = _FakeNovelRepository();
    await tester.pumpWidget(_buildReaderApp(repository: repository));
    await tester.pumpAndSettle();

    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-bookmark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-reader-add-position-bookmark')));
    await tester.pumpAndSettle();

    final position = repository.bookmarks.singleWhere(
      (bookmark) => bookmark.bookmarkId.startsWith('reader-bookmark:'),
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _showReaderMenu(tester);
    await tester.tap(find.byKey(const Key('shared-reader-bottom-action-bookmark')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('novel-reader-remove-bookmark-${position.bookmarkId}')),
    );
    await tester.pumpAndSettle();

    expect(
      repository.bookmarks.where(
        (bookmark) => bookmark.bookmarkId == position.bookmarkId,
      ),
      isEmpty,
    );
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
  String initialEpisodeId = 'novel:49:100:5001',
}) {
  return ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      forumWebViewExternalLauncherProvider.overrideWithValue(
        _FakeForumWebViewExternalLauncher(),
      ),
      imageRequestHeaderBuilderProvider.overrideWithValue(
        const _StaticImageHeaderBuilder(),
      ),
      novelDownloadServiceProvider.overrideWithValue(
        downloadService ?? _NoopNovelDownloadService(),
      ),
      if (threadRepository != null)
        threadRepositoryProvider.overrideWithValue(threadRepository),
    ],
    child: MaterialApp(
      home: NovelReaderPage(
        novelId: 'novel:49:100',
        initialEpisodeId: initialEpisodeId,
      ),
    ),
  );
}

class _FakeForumWebViewExternalLauncher implements ForumWebViewExternalLauncher {
  @override
  Future<bool> launch(Uri uri) async => true;
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
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
    String? firstRawHtml,
    NovelReaderPreferences? preferences,
    List<NovelEpisodeItem>? episodes,
    Map<String, NovelChapterContent>? contentsByEpisodeId,
    this.readingProgress,
  })  : episodes = episodes ?? _defaultEpisodes(),
        contentsByEpisodeId = contentsByEpisodeId ??
            _defaultContents(
              firstParagraphs: firstParagraphs,
              firstRawHtml: firstRawHtml,
            ),
        preferences = preferences ?? NovelReaderPreferences.defaults();

  factory _FakeNovelRepository.threeEpisodes({
    NovelReadingProgress? readingProgress,
  }) {
    return _FakeNovelRepository(
      episodes: _threeEpisodes(),
      contentsByEpisodeId: _contentsForParagraphs(
        const <String, List<String>>{
          'novel:49:100:5001': <String>['第一段。', '第二段。'],
          'novel:49:100:5002': <String>['第三段。', '第四段。'],
          'novel:49:100:5003': <String>['第五段。', '第六段。'],
        },
      ),
      readingProgress: readingProgress,
    );
  }

  factory _FakeNovelRepository.manyEpisodes({
    required int count,
    required int currentIndex,
  }) {
    final episodes = List<NovelEpisodeItem>.generate(count, (index) {
      final number = index + 1;
      final pid = (5000 + number).toString();
      return NovelEpisodeItem(
        episodeId: 'novel:49:100:$pid',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: pid,
        sourcePage: 1,
        episodeTitle: '第$number章',
        orderIndex: index,
        datelineText: '2026-05-${number.toString().padLeft(2, '0')}',
      );
    });
    final contents = <String, NovelChapterContent>{
      for (final episode in episodes)
        episode.episodeId: _contentFromParagraphs(
          episode.episodeId,
          <String>['${episode.episodeTitle}正文。'],
        ),
    };
    return _FakeNovelRepository(
      episodes: episodes,
      contentsByEpisodeId: contents,
      readingProgress: NovelReadingProgress(
        novelId: 'novel:49:100',
        episodeId: episodes[currentIndex].episodeId,
        scrollOffset: 0,
        updatedAt: DateTime(2026, 6, 1),
      ),
    );
  }

  final List<NovelEpisodeItem> episodes;
  final Map<String, NovelChapterContent> contentsByEpisodeId;
  NovelReadingProgress? readingProgress;
  NovelReaderPreferences preferences;
  NovelReaderPreferences? latestPreferences;
  double lastSavedOffset = 0;
  final savedProgressEpisodeIds = <String>[];
  final bookmarks = <NovelReaderBookmark>[];

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
      episodeCount: episodes.length,
    );
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return contentsByEpisodeId[episodeId];
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
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
    return readingProgress;
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: episodes.length,
    );
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
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    lastSavedOffset = scrollOffset;
    readingProgress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 6, 8),
      flowMode: flowMode,
      pageIndex: pageIndex,
      anchorNodeId: anchorNodeId,
      progressPercent: progressPercent,
    );
  }

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    latestPreferences = preferences;
    this.preferences = preferences;
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    bookmarks.removeWhere((item) => item.bookmarkId == bookmark.bookmarkId);
    bookmarks.add(bookmark);
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return bookmarks.where((bookmark) => bookmark.novelId == novelId).toList();
  }

  @override
  Future<void> removeReaderBookmark({
    required String bookmarkId,
  }) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == bookmarkId);
  }

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    bookmarks.removeWhere(
      (bookmark) => bookmark.bookmarkId == 'episode-bookmark:$episodeId',
    );
    if (!isBookmarked) {
      return;
    }
    final episode = episodes.firstWhere((item) => item.episodeId == episodeId);
    bookmarks.add(
      NovelReaderBookmark(
        bookmarkId: 'episode-bookmark:$episodeId',
        novelId: novelId,
        episodeId: episodeId,
        anchor: NovelReaderTextAnchor(episodeId: episodeId),
        title: episode.episodeTitle,
        snippet: '章节书签',
        createdAt: DateTime(2026, 6, 8),
        updatedAt: DateTime(2026, 6, 8),
      ),
    );
  }

  static String _rawHtmlFromParagraphs(List<String> paragraphs) {
    return paragraphs.map((paragraph) => '<p>$paragraph</p>').join();
  }

  static List<NovelEpisodeItem> _defaultEpisodes() {
    return _threeEpisodes().take(2).toList(growable: false);
  }

  static List<NovelEpisodeItem> _threeEpisodes() {
    return const <NovelEpisodeItem>[
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
      NovelEpisodeItem(
        episodeId: 'novel:49:100:5003',
        novelId: 'novel:49:100',
        sourceTid: '100',
        sourcePid: '5003',
        sourcePage: 1,
        episodeTitle: '第3章',
        orderIndex: 2,
        datelineText: '2026-05-05',
      ),
    ];
  }

  static Map<String, NovelChapterContent> _defaultContents({
    List<String>? firstParagraphs,
    String? firstRawHtml,
  }) {
    final paragraphs = firstParagraphs ?? const <String>['第一段。', '第二段。'];
    final rawHtml = firstRawHtml ?? _rawHtmlFromParagraphs(paragraphs);
    return <String, NovelChapterContent>{
      'novel:49:100:5001': NovelChapterContent(
        episodeId: 'novel:49:100:5001',
        rawHtml: rawHtml,
        plainText: paragraphs.join('\n'),
        paragraphs: paragraphs,
      ),
      'novel:49:100:5002': const NovelChapterContent(
        episodeId: 'novel:49:100:5002',
        rawHtml: '<p>第三段。</p><p>第四段。</p>',
        plainText: '第三段。\n第四段。',
        paragraphs: <String>['第三段。', '第四段。'],
      ),
    };
  }

  static Map<String, NovelChapterContent> _contentsForParagraphs(
    Map<String, List<String>> source,
  ) {
    return <String, NovelChapterContent>{
      for (final entry in source.entries)
        entry.key: _contentFromParagraphs(entry.key, entry.value),
    };
  }

  static NovelChapterContent _contentFromParagraphs(
    String episodeId,
    List<String> paragraphs,
  ) {
    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: _rawHtmlFromParagraphs(paragraphs),
      plainText: paragraphs.join('\n'),
      paragraphs: paragraphs,
    );
  }
}
