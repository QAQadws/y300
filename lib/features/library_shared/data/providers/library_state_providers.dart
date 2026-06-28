import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/data/services/reading_state_batch_writer_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';

/// 统一状态仓储 Provider。
final libraryStateRepositoryProvider = Provider<LibraryStateRepository>((ref) {
  return LocalLibraryStateRepository(ComicLocalDb.open());
});

final readingStateBatchWriterProvider = Provider<ReadingStateBatchWriter>((ref) {
  return DefaultReadingStateBatchWriter(
    stateRepository: ref.watch(libraryStateRepositoryProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});
