import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/widgets/reader_bottom_panel.dart';

void main() {
  testWidgets('toolbar buttons trigger reader actions', (tester) async {
    var modeOpened = false;
    var chapterOpened = false;
    var settingsOpened = false;
    var cacheTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderBottomPanel(
            currentMode: ReaderModePreference.vertical,
            currentPage: 1,
            totalPages: 12,
            hasPreviousEpisode: true,
            hasNextEpisode: true,
            nextChapterPreload: const ComicReaderChapterPreloadState(
              status: ComicReaderChapterPreloadStatus.idle,
              episodeId: 'next',
              title: '第2话',
            ),
            onPreviousEpisode: () {},
            onNextEpisode: () {},
            onOpenModeSheet: () => modeOpened = true,
            onOpenChapterList: () => chapterOpened = true,
            onOpenDisplaySettings: () => settingsOpened = true,
            onCacheEpisode: () => cacheTapped = true,
            onProgressChangeStart: (_) {},
            onProgressChanged: (_) {},
            onProgressChangeEnd: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('comic-reader-mode-switch')));
    await tester.tap(find.byKey(const Key('comic-reader-chapter-list-button')));
    await tester.tap(find.byKey(const Key('comic-reader-display-settings-button')));
    await tester.tap(find.byKey(const Key('comic-reader-bottom-cache-button')));
    await tester.pumpAndSettle();

    expect(modeOpened, isTrue);
    expect(chapterOpened, isTrue);
    expect(settingsOpened, isTrue);
    expect(cacheTapped, isTrue);
  });

  testWidgets('narrow screen keeps controls within viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderBottomPanel(
              currentMode: ReaderModePreference.rtl,
              currentPage: 88,
              totalPages: 120,
              hasPreviousEpisode: true,
              hasNextEpisode: true,
              nextChapterPreload: const ComicReaderChapterPreloadState(
                status: ComicReaderChapterPreloadStatus.preloadingPages,
                episodeId: 'next',
                title: '很长很长很长的下一话标题',
              ),
              onPreviousEpisode: () {},
              onNextEpisode: () {},
              onOpenModeSheet: () {},
              onOpenChapterList: () {},
              onOpenDisplaySettings: () {},
              onCacheEpisode: () {},
              onProgressChangeStart: (_) {},
              onProgressChanged: (_) {},
              onProgressChangeEnd: (_) {},
            ),
          ),
        ),
      ),
    );

    final viewport = Rect.fromLTWH(
      0,
      0,
      tester.view.physicalSize.width,
      tester.view.physicalSize.height,
    );
    for (final key in const <Key>[
      Key('comic-reader-prev-episode-button'),
      Key('comic-reader-next-episode-button'),
      Key('comic-reader-mode-switch'),
      Key('comic-reader-chapter-list-button'),
      Key('comic-reader-display-settings-button'),
      Key('comic-reader-bottom-cache-button'),
    ]) {
      expect(viewport.contains(tester.getCenter(find.byKey(key))), isTrue);
    }
  });
}
