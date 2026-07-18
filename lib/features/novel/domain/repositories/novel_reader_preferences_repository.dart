import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

abstract interface class NovelReaderPreferencesRepository {
  Future<NovelReaderPreferences> load();

  Future<void> save(NovelReaderPreferences preferences);
}
