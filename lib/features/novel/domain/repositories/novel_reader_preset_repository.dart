import 'package:characters/characters.dart';

import '../models/novel_reader_preferences.dart';

final class NovelReaderPreset {
  const NovelReaderPreset({
    required this.id,
    required this.name,
    required this.preferences,
  });

  static const maxNameLength = 60;

  final String id;
  final String name;

  /// Metadata remains visible when this version cannot apply the settings.
  final NovelReaderPreferences? preferences;

  static bool isValidName(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty && trimmed.characters.length <= maxNameLength;
  }
}

abstract interface class NovelReaderPresetRepository {
  Future<List<NovelReaderPreset>> load();

  Future<List<NovelReaderPreset>> save(
    String name,
    NovelReaderPreferences preferences,
  );

  Future<List<NovelReaderPreset>> rename(String id, String name);

  Future<List<NovelReaderPreset>> reset(String id);
}

typedef NovelReaderPresetApplication = ({
  NovelReaderPreferences preferences,
  bool keepCurrentFont,
});
