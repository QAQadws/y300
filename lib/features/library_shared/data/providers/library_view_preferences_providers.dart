import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_legacy_source.dart';
import 'package:y300/features/library_shared/data/preferences/shared_preferences_library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';

final libraryViewPreferencesLegacySourceProvider =
    Provider<LibraryViewPreferencesLegacySource>((ref) {
      return SqliteLibraryViewPreferencesLegacySource(() => AppDatabase.open());
    });

final libraryViewPreferencesRepositoryProvider =
    Provider<LibraryViewPreferencesRepository>((ref) {
      return SharedPreferencesLibraryViewPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
        legacySource: ref.watch(libraryViewPreferencesLegacySourceProvider),
      );
    });
