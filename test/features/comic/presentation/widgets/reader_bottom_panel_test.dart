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
}
