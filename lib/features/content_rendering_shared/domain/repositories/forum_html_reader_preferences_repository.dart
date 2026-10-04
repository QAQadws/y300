import 'package:y300/features/content_rendering_shared/domain/models/forum_html_reader_preferences.dart';

abstract class ForumHtmlReaderPreferencesRepository {
  Future<ForumHtmlReaderPreferences> load();

  Future<void> save(ForumHtmlReaderPreferences preferences);
}
