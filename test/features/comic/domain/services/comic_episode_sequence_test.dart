import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_sequence.dart';

void main() {
  const sequence = ComicEpisodeSequence();

  test('orders numeric tids and stabilizes duplicate tids', () {
    const episodes = <ComicEpisodeItem>[
      ComicEpisodeItem(
        episodeId: 'comic:10',
        comicId: 'comic',
        episodeTitle: '10',
        sourceTid: '10',
        sourceUrl: 'thread-10.html',
        orderIndex: 2,
        publishTimeText: null,
      ),
      ComicEpisodeItem(
        episodeId: 'comic:2-late',
        comicId: 'comic',
        episodeTitle: '2 late',
        sourceTid: '2',
        sourceUrl: 'thread-2-late.html',
        orderIndex: 2,
        publishTimeText: null,
      ),
      ComicEpisodeItem(
        episodeId: 'comic:2-first',
        comicId: 'comic',
        episodeTitle: '2 first',
        sourceTid: '2',
        sourceUrl: 'thread-2-first.html',
        orderIndex: 1,
        publishTimeText: null,
      ),
    ];

    expect(
      sequence.order(episodes).map((episode) => episode.episodeId),
      <String>['comic:2-first', 'comic:2-late', 'comic:10'],
    );
    expect(
      sequence
          .adjacent(
            episodes: episodes,
            episodeId: 'comic:2-late',
            direction: ComicEpisodeDirection.next,
          )
          ?.episodeId,
      'comic:10',
    );
  });

  test('returns no adjacent episode when the current id is unknown', () {
    expect(
      sequence.adjacent(
        episodes: const <ComicEpisodeItem>[],
        episodeId: 'comic:missing',
        direction: ComicEpisodeDirection.next,
      ),
      isNull,
    );
  });
}
