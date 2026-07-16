import 'package:y300/features/history/data/local/history_database_manager.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';

class HistoryDataLifecycleService {
  const HistoryDataLifecycleService({
    required HistoryDatabaseManager databaseManager,
    required HistoryRepository repository,
  }) : _databaseManager = databaseManager,
       _repository = repository;

  final HistoryDatabaseManager _databaseManager;
  final HistoryRepository _repository;

  /// Removes history as one contributor to a full application-data reset.
  ///
  /// Ordinary cache cleanup must never call this method. When the history
  /// connection is active, clear through the repository first so an existing
  /// HistoryController receives its normal change event before the file is
  /// closed and deleted.
  Future<void> deleteAllData() async {
    if (_databaseManager.isInitialized) {
      try {
        await _repository.clear();
      } catch (_) {
        // A full reset can still recover from a corrupt table by deleting the
        // closed database file below.
      }
    }
    await _databaseManager.deleteAllData();
  }
}
