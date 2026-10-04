import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/storage/data/sqlite_metadata_storage_accounting_adapter.dart';

class ComicMetadataStorageAccountingAdapter
    extends SqliteMetadataStorageAccountingAdapter {
  const ComicMetadataStorageAccountingAdapter({
    super.databaseProvider = AppDatabase.open,
  }) : super(
         tables: const <String, String>{
           'comics': AppDatabase.comicsTable,
           'comic_episodes': AppDatabase.episodesTable,
         },
       );
}
