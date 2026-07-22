import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

abstract interface class ComicDownloadQueue {
  ValueListenable<ComicDownloadQueueSnapshot> get snapshot;

  Future<ComicDownloadEnqueueResult> enqueueTargets(
    Iterable<ComicDownloadTarget> targets,
  );

  Future<void> cancel(int taskId);

  Future<void> retry(int taskId);

  Future<void> remove(int taskId);

  Future<void> cancelEpisode(String comicId, String episodeId);

  Future<void> cancelComic(String comicId);

  Future<void> start();
}
