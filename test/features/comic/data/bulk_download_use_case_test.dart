import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/use_cases/bulk_download_use_case_impl.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';

void main() {
  test('builds ordered chapter targets and enqueues them once', () async {
    final repository = _FakeComicRepository(
      episodesByComicId: <String, List<ComicEpisodeItem>>{
        'comic:1': _episodes('comic:1', 2),
        'comic:2': _episodes('comic:2', 1),
      },
    );
    final queue = _RecordingDownloadQueue();
    final useCase = DefaultBulkDownloadUseCase(
      comicRepository: repository,
      downloadQueue: queue,
    );

    final result = await useCase.downloadComics(<String>{'comic:1', 'comic:2'});

    expect(
      queue.targets.map((target) => '${target.comicId}/${target.episodeId}'),
      <String>['comic:1/comic:1:1', 'comic:1/comic:1:2', 'comic:2/comic:2:1'],
    );
    expect(result.requestedCount, 3);
    expect(result.enqueuedCount, 3);
    expect(result.deduplicatedCount, 0);
    expect(result.skippedDownloadedCount, 0);
  });

  test('ignores blank comic ids without creating queue targets', () async {
    final queue = _RecordingDownloadQueue();
    final useCase = DefaultBulkDownloadUseCase(
      comicRepository: _FakeComicRepository(
        episodesByComicId: const <String, List<ComicEpisodeItem>>{},
      ),
      downloadQueue: queue,
    );

    final result = await useCase.downloadComics(<String>{'', '  '});

    expect(queue.targets, isEmpty);
    expect(result.requestedCount, 0);
    expect(result.enqueuedCount, 0);
  });
}

List<ComicEpisodeItem> _episodes(String comicId, int count) {
  return List<ComicEpisodeItem>.generate(count, (index) {
    final number = index + 1;
    return ComicEpisodeItem(
      episodeId: '$comicId:$number',
      comicId: comicId,
      episodeTitle: '第 $number 话',
      sourceTid: '$number',
      sourceUrl: 'thread-$number-1-1.html',
      orderIndex: index,
      publishTimeText: null,
    );
  });
}

final class _FakeComicRepository implements ComicRepository {
  _FakeComicRepository({required this.episodesByComicId});

  final Map<String, List<ComicEpisodeItem>> episodesByComicId;

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: comicId,
      sourceFid: '30',
      title: '作品 $comicId',
      author: null,
      translationGroup: null,
      coverImageUrl: null,
      updatedAt: DateTime(2026),
      episodeCount: episodesByComicId[comicId]?.length ?? 0,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    return episodesByComicId[comicId] ?? const <ComicEpisodeItem>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingDownloadQueue implements ComicDownloadQueue {
  final List<ComicDownloadTarget> targets = <ComicDownloadTarget>[];
  final ValueNotifier<ComicDownloadQueueSnapshot> _snapshot =
      ValueNotifier<ComicDownloadQueueSnapshot>(
        ComicDownloadQueueSnapshot.empty,
      );

  @override
  ValueListenable<ComicDownloadQueueSnapshot> get snapshot => _snapshot;

  @override
  Future<ComicDownloadEnqueueResult> enqueueTargets(
    Iterable<ComicDownloadTarget> targets,
  ) async {
    this.targets.addAll(targets);
    return ComicDownloadEnqueueResult(
      requestedCount: this.targets.length,
      enqueuedCount: this.targets.length,
      deduplicatedCount: 0,
      skippedDownloadedCount: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
