import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

abstract class ComicDownloadService {
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  });

  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  });

  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  });
}
