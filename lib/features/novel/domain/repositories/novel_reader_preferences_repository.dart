import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

abstract interface class NovelReaderPreferencesRepository {
  Future<NovelReaderPreferences> load();

  Future<void> save(NovelReaderPreferences preferences);
}

/// The running version cannot safely edit this stored preference format.
/// No serialized payload is carried through the failure/UI boundary.
final class NovelReaderPreferencesUnsupportedSnapshot implements Exception {
  const NovelReaderPreferencesUnsupportedSnapshot();

  @override
  String toString() => 'NovelReaderPreferencesUnsupportedSnapshot';
}
