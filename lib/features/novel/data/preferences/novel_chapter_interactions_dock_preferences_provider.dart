import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_chapter_interactions_dock_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';

final novelChapterInteractionsDockPreferencesRepositoryProvider =
    Provider<NovelChapterInteractionsDockPreferencesRepository>((ref) {
      return SharedPreferencesNovelChapterInteractionsDockRepository(
        ref.watch(preferencesStoreProvider),
      );
    });
