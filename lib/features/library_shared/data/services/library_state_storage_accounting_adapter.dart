import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/storage/data/sqlite_metadata_storage_accounting_adapter.dart';

class LibraryStateStorageAccountingAdapter
    extends SqliteMetadataStorageAccountingAdapter {
  const LibraryStateStorageAccountingAdapter({
    super.databaseProvider = AppDatabase.open,
  }) : super(
         tables: const <String, String>{
           'library_work_state': AppDatabase.libraryWorkStateTable,
           'library_episode_state': AppDatabase.libraryEpisodeStateTable,
         },
       );
}
