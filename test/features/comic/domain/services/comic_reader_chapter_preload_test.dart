import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';

void main() {
  test('policy uses two trailing pages for short chapters', () {
    const policy = ComicReaderChapterPreloadPolicy();

    expect(
      policy.shouldPreloadNextChapter(currentImageIndex: 3, totalImages: 6),
      isFalse,
    );
    expect(
      policy.shouldPreloadNextChapter(currentImageIndex: 4, totalImages: 6),
      isTrue,
    );
  });

  test('policy uses four trailing pages for long chapters', () {
    const policy = ComicReaderChapterPreloadPolicy();

    expect(
      policy.shouldPreloadNextChapter(currentImageIndex: 5, totalImages: 10),
      isFalse,
    );
    expect(
      policy.shouldPreloadNextChapter(currentImageIndex: 6, totalImages: 10),
      isTrue,
    );
  });

  test('state exposes stable display title and open semantics', () {
    const episode = ComicEpisodeItem(
      episodeId: 'comic:1:2',
      comicId: 'comic:1',
      episodeTitle: null,
      sourceTid: '222',
      sourceUrl: 'thread-222-1-1.html',
      orderIndex: 1,
      publishTimeText: null,
    );

    final state = ComicReaderChapterPreloadState.idle(episode);

    expect(state.displayTitle, '章节 222');
    expect(state.canOpen, isTrue);
    expect(ComicReaderChapterPreloadState.unavailable().canOpen, isFalse);
  });

  test('policy caps first page preload window at three images', () {
    const policy = ComicReaderChapterPreloadPolicy();

    expect(policy.firstPageWindowLength(0), 0);
    expect(policy.firstPageWindowLength(2), 2);
    expect(policy.firstPageWindowLength(8), 3);
  });
}
