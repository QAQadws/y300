import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_legacy_migrator.dart';

final libraryCoverLegacyMigratorProvider = Provider<LibraryCoverLegacyMigrator>(
  (ref) {
    return LibraryCoverLegacyMigrator(
      database: ComicLocalDb.open(),
      store: ref.watch(libraryCoverStoreProvider),
      legacyCacheRepository: ref.watch(imageCacheRepositoryProvider),
    );
  },
);
