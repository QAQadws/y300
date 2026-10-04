import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/storage/data/sqlite_metadata_storage_accounting_adapter.dart';

class NovelMetadataStorageAccountingAdapter
    extends SqliteMetadataStorageAccountingAdapter {
  const NovelMetadataStorageAccountingAdapter({
    super.databaseProvider = AppDatabase.open,
  }) : super(
         tables: const <String, String>{
           'novels': AppDatabase.worksTable,
           'novel_episodes': AppDatabase.workEpisodesTable,
         },
       );
}
