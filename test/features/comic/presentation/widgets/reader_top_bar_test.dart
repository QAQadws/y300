import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/widgets/reader_top_bar.dart';

void main() {
  testWidgets('top bar shows two-line title and primary actions', (tester) async {
    var bookmarkTapped = false;
    var detailTapped = false;
    var threadTapped = false;
    ReaderMoreAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderTopBar(
            comicTitle: '作品标题',
            episodeTitle: '第1话',
            isBookmarked: false,
            isCurrentEpisodeRead: false,
            failedImageCount: 2,
            onBack: () {},
            onOpenDetail: () => detailTapped = true,
            onToggleBookmark: () => bookmarkTapped = true,
            onOpenThread: () => threadTapped = true,
            onMoreActionSelected: (value) => selectedAction = value,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('comic-reader-top-comic-title')), findsOneWidget);
    expect(find.byKey(const Key('comic-reader-top-episode-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('comic-reader-title-button')));
    await tester.tap(find.byKey(const Key('comic-reader-bookmark-button')));
    await tester.tap(find.byKey(const Key('comic-reader-open-thread-button')));
    await tester.tap(find.byKey(const Key('comic-reader-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-reader-set-cover')));
    await tester.pumpAndSettle();

    expect(detailTapped, isTrue);
    expect(bookmarkTapped, isTrue);
    expect(threadTapped, isTrue);
    expect(selectedAction, ReaderMoreAction.setCurrentPageAsCover);
  });

  testWidgets('long title keeps ellipsis on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderTopBar(
            comicTitle: '这是一个非常非常非常非常长的漫画标题用于验证省略号',
            episodeTitle: '这是一个非常非常非常长的章节标题用于验证省略号',
            isBookmarked: true,
            isCurrentEpisodeRead: true,
            failedImageCount: 0,
            onBack: () {},
            onOpenDetail: () {},
            onToggleBookmark: () {},
            onOpenThread: () {},
            onMoreActionSelected: (_) {},
          ),
        ),
      ),
    );

    final comicTitle = tester.widget<Text>(
      find.byKey(const Key('comic-reader-top-comic-title')),
    );
    final episodeTitle = tester.widget<Text>(
      find.byKey(const Key('comic-reader-top-episode-title')),
    );
    expect(comicTitle.maxLines, 1);
    expect(comicTitle.overflow, TextOverflow.ellipsis);
    expect(episodeTitle.maxLines, 1);
    expect(episodeTitle.overflow, TextOverflow.ellipsis);
  });
}
