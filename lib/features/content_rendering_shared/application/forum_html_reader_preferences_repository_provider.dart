import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/content_rendering_shared/data/repositories/shared_prefs_forum_html_reader_preferences_repository.dart';
import 'package:y300/features/content_rendering_shared/domain/repositories/forum_html_reader_preferences_repository.dart';

final forumHtmlReaderPreferencesRepositoryProvider =
    Provider<ForumHtmlReaderPreferencesRepository>(
      (ref) => SharedPrefsForumHtmlReaderPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      ),
    );
