import 'dart:convert';

import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/fonts/fonts.dart' show FontIdentity;

import '../../domain/models/novel_reader_preferences.dart';
import '../../domain/repositories/novel_reader_preferences_repository.dart';
import '../../domain/repositories/novel_reader_preset_repository.dart';
import 'novel_reader_preferences_snapshot_codec.dart';

final class SharedPreferencesNovelReaderPresetRepository
    implements NovelReaderPresetRepository {
  SharedPreferencesNovelReaderPresetRepository(this._store);

  static const _version = 1;
  static const _key = PreferenceKeys.novelReaderPresetsV1;
  static const _snapshot = NovelReaderPreferencesSnapshotCodec();
  static const _requiredSettings = {
    'fontSize',
    'lineHeight',
    'fontFamily',
    'flowMode',
    'themePreset',
    'conversionMode',
    'safeAreaEnabled',
  };
  static const _optionalFlags = {
    'compressBlankLines',
    'removeSourceIndent',
    'avoidIsolatedLines',
    'keepHeadingWithNext',
    'showRubyAnnotations',
  };
  final PreferencesStore _store;
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<NovelReaderPreset>> load() => _enqueue(() async {
    final library = await _read();
    return _presets(library['presets'] as Map<String, dynamic>);
  });

  @override
  Future<List<NovelReaderPreset>> save(
    String name,
    NovelReaderPreferences preferences,
  ) => _mutate((entries) {
    var id = DateTime.now().microsecondsSinceEpoch;
    while (entries.containsKey(id.toString())) {
      id++;
    }
    entries[id.toString()] = {
      'name': _name(name),
      'settings': jsonDecode(_snapshot.encode(preferences)),
    };
  });

  @override
  Future<List<NovelReaderPreset>> rename(String id, String name) =>
      _mutate((entries) => _entry(entries, id)['name'] = _name(name));

  @override
  Future<List<NovelReaderPreset>> reset(String id) => _mutate((entries) {
    final entry = _entry(entries, id);
    final settings = entry['settings'];
    if (_preferences(settings) == null) {
      throw const NovelReaderPreferencesUnsupportedSnapshot();
    }
    entry['settings'] = jsonDecode(
      _snapshot.encode(
        NovelReaderPreferences.defaults(),
        previousSource: jsonEncode(settings),
      ),
    );
  });

  Future<List<NovelReaderPreset>> _mutate(
    void Function(Map<String, dynamic> entries) change,
  ) => _enqueue(() async {
    final library = await _read();
    final entries = library['presets'] as Map<String, dynamic>;
    change(entries);
    await _store.write(_key, jsonEncode(library));
    return _presets(entries);
  });

  Future<Map<String, dynamic>> _read() async {
    final raw = await _store.read(_key);
    if (raw == null && !await _store.contains(_key)) {
      return {'schemaVersion': _version, 'presets': <String, dynamic>{}};
    }
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['schemaVersion'] == _version &&
          decoded['presets'] is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // An explicit edit still has to preserve the original library.
    }
    throw const NovelReaderPreferencesUnsupportedSnapshot();
  }

  List<NovelReaderPreset> _presets(Map<String, dynamic> entries) =>
      List.unmodifiable([
        for (final id in entries.keys.toList().reversed)
          if (entries[id]
              case {'name': final String name, 'settings': final settings}
              when NovelReaderPreset.isValidName(name))
            NovelReaderPreset(
              id: id,
              name: name,
              preferences: _preferences(settings),
            ),
      ]);

  NovelReaderPreferences? _preferences(Object? settings) {
    if (settings is! Map<String, dynamic> ||
        settings['schemaVersion'] !=
            NovelReaderPreferencesSnapshotCodec.schemaVersion) {
      return null;
    }
    final font = settings['fontFamily'];
    if (font is! String ||
        (font != FontIdentity.system && !FontIdentity.isImported(font))) {
      return null;
    }
    final source = jsonEncode(settings);
    final prefs = _snapshot.decode(source);
    try {
      // Check the complete shape before applying a preset. The ordinary
      // reader decoder is deliberately permissive when opening old settings.
      final canonical =
          jsonDecode(_snapshot.encode(prefs, previousSource: source)) as Map;
      if (_requiredSettings.any((key) => settings[key] != canonical[key]) ||
          _optionalFlags.any(
            (key) => settings.containsKey(key) && settings[key] is! bool,
          )) {
        return null;
      }
      return prefs;
    } on NovelReaderPreferencesUnsupportedSnapshot {
      return null;
    }
  }

  static Map<String, dynamic> _entry(Map<String, dynamic> entries, String id) {
    final entry = entries[id];
    if (entry is! Map<String, dynamic> || entry['name'] is! String) {
      throw StateError('Preset unavailable');
    }
    return entry;
  }

  static String _name(String name) {
    if (!NovelReaderPreset.isValidName(name)) {
      throw ArgumentError('Invalid preset name');
    }
    return name.trim();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
