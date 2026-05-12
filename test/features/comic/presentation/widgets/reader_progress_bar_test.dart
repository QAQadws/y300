import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';
import 'package:y300/features/comic/presentation/widgets/reader_progress_bar.dart';

void main() {
  testWidgets('progress bar renders current/total labels and triggers callbacks', (tester) async {
    var changed = false;
    var ended = false;
    var previousTapped = false;
    var nextTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderProgressBar(
            currentPage: 1,
            totalPages: 5,
            hasPreviousEpisode: true,
            hasNextEpisode: true,
            nextChapterPreload: const ComicReaderChapterPreloadState(
              status: ComicReaderChapterPreloadStatus.idle,
              episodeId: 'next',
              title: '第2话',
            ),
            onPreviousEpisode: () => previousTapped = true,
            onNextEpisode: () => nextTapped = true,
            onChanged: (_) => changed = true,
            onChangeEnd: (_) => ended = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('comic-reader-current-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-total-page-label')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-progress-slider')), findsOneWidget);

    await tester.tap(find.byKey(const Key('comic-reader-prev-episode-button')));
    await tester.tap(find.byKey(const Key('comic-reader-next-episode-button')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('comic-reader-progress-slider')),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();

    expect(previousTapped, isTrue);
    expect(nextTapped, isTrue);
    expect(changed, isTrue);
    expect(ended, isTrue);
  });

  testWidgets('progress bar disables slider interaction when locked', (tester) async {
    var changed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderProgressBar(
            currentPage: 2,
            totalPages: 8,
            hasPreviousEpisode: true,
            hasNextEpisode: true,
            nextChapterPreload: const ComicReaderChapterPreloadState(
              status: ComicReaderChapterPreloadStatus.ready,
              episodeId: 'next',
              title: '第2话',
              cachedPageCount: 3,
            ),
            onPreviousEpisode: () {},
            onNextEpisode: () {},
            onChanged: (_) => changed = true,
            onChangeEnd: (_) {},
            interactionLocked: true,
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const Key('comic-reader-progress-slider')),
      const Offset(180, 0),
    );
    await tester.pumpAndSettle();

    expect(changed, isFalse);
  });
}
