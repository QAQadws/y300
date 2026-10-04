import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/services/comic_metadata_storage_accounting_adapter.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_storage_accounting_adapter.dart';
import 'package:y300/features/favorites/data/services/favorite_metadata_storage_accounting_adapter.dart';
import 'package:y300/features/library_shared/data/services/library_state_storage_accounting_adapter.dart';
import 'package:y300/features/novel/data/services/novel_metadata_storage_accounting_adapter.dart';
import 'package:y300/features/profile/data/services/blog_draft_storage_accounting_adapter.dart';
import 'package:y300/features/profile/domain/repositories/blog_draft_repository.dart';
import 'package:y300/features/storage/data/composite_storage_accounting_adapter.dart';
import 'package:y300/features/storage/data/shared_library_database_storage_accounting_adapter.dart';

StorageAccountingAdapter composeLibraryMetadataStorageAccountingAdapter({
  Future<Database> Function() databaseProvider = AppDatabase.open,
  Future<String>? databasePathFuture,
}) => CompositeStorageAccountingAdapter(
  bucket: StorageBucket.libraryMetadata,
  adapters: <StorageAccountingAdapter>[
    // The physical file is registered once; every owner below contributes
    // only row-count slices in the existing overview order.
    SharedLibraryDatabaseStorageAccountingAdapter(
      databaseProvider: databaseProvider,
      databasePathFuture: databasePathFuture,
    ),
    ComicMetadataStorageAccountingAdapter(databaseProvider: databaseProvider),
    NovelMetadataStorageAccountingAdapter(databaseProvider: databaseProvider),
    FavoriteMetadataStorageAccountingAdapter(
      databaseProvider: databaseProvider,
    ),
    LibraryStateStorageAccountingAdapter(databaseProvider: databaseProvider),
  ],
);

StorageAccountingAdapter composeComposerDraftStorageAccountingAdapter({
  required Future<Database> Function() databaseProvider,
  BlogDraftRepository? blogDraftRepository,
}) => CompositeStorageAccountingAdapter(
  bucket: StorageBucket.composerDraft,
  adapters: <StorageAccountingAdapter>[
    if (blogDraftRepository != null)
      BlogDraftStorageAccountingAdapter(repository: blogDraftRepository),
    ComposerDraftStorageAccountingAdapter(databaseProvider: databaseProvider),
  ],
);
