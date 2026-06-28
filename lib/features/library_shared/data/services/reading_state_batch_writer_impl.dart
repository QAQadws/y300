import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';

class DefaultReadingStateBatchWriter implements ReadingStateBatchWriter {
  const DefaultReadingStateBatchWriter({
    required LibraryStateRepository stateRepository,
    required LibraryShelfRefreshBus shelfRefreshBus,
  }) : _stateRepository = stateRepository,
       _shelfRefreshBus = shelfRefreshBus;

  final LibraryStateRepository _stateRepository;
  final LibraryShelfRefreshBus _shelfRefreshBus;

  @override
  Future<void> setWorkRead({
    required LibraryModuleKey module,
    required String workId,
    required bool isRead,
  }) async {
    final normalizedWorkId = workId.trim();
    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workId must not be empty');
    }
    await setWorksRead(
      module: module,
      workIds: <String>{normalizedWorkId},
      isRead: isRead,
    );
  }

  @override
  Future<void> setWorksRead({
    required LibraryModuleKey module,
    required Set<String> workIds,
    required bool isRead,
  }) async {
    final normalizedWorkIds = workIds
        .map((workId) => workId.trim())
        .where((workId) => workId.isNotEmpty)
        .toSet();
    if (normalizedWorkIds.isEmpty) {
      return;
    }
    final effectiveReadAt = isRead ? DateTime.now() : null;
    await _stateRepository.setWorksReadState(
      moduleKey: module,
      workIds: normalizedWorkIds,
      isRead: isRead,
      readAt: effectiveReadAt,
    );

    final isSingle = normalizedWorkIds.length == 1;
    final onlyWorkId = isSingle ? normalizedWorkIds.first : null;
    _shelfRefreshBus.notify(
      modules: <LibraryModuleKey>{module},
      reason: _reasonFor(
        isSingle: isSingle,
        isRead: isRead,
      ),
      source: LibraryMutationSource.readingStateBatch,
      workId: onlyWorkId,
      payload: <String, Object?>{
        'workIdCount': normalizedWorkIds.length,
        'isRead': isRead,
      },
    );
  }

  String _reasonFor({
    required bool isSingle,
    required bool isRead,
  }) {
    if (isSingle) {
      return isRead
          ? 'work_mark_all_read_completed'
          : 'work_mark_all_unread_completed';
    }
    return isRead
        ? 'works_mark_all_read_completed'
        : 'works_mark_all_unread_completed';
  }
}
