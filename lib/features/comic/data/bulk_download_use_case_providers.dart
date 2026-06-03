import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/bulk_download_use_case_impl.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_task_progress_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

final bulkDownloadUseCaseProvider = Provider<BulkDownloadUseCase>((ref) {
  return DefaultBulkDownloadUseCase(
    comicRepository: ref.watch(comicRepositoryProvider),
    downloadService: ref.watch(comicDownloadServiceProvider),
    libraryStateRepository: ref.watch(libraryStateRepositoryProvider),
    taskProgressHub: ref.watch(libraryTaskProgressHubProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});
