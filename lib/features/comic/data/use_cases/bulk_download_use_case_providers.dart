import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/use_cases/bulk_download_use_case_impl.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';

final bulkDownloadUseCaseProvider = Provider<BulkDownloadUseCase>((ref) {
  return DefaultBulkDownloadUseCase(
    comicRepository: ref.watch(comicRepositoryProvider),
    downloadQueue: ref.watch(comicDownloadQueueProvider),
  );
});
