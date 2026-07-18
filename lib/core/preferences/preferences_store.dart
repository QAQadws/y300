import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_key.dart';

abstract interface class PreferencesStore {
  Future<T?> read<T extends Object>(PreferenceKey<T> key);

  Future<bool> contains<T extends Object>(PreferenceKey<T> key);

  Future<void> write<T extends Object>(PreferenceKey<T> key, T value);

  Future<void> remove<T extends Object>(PreferenceKey<T> key);
}

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

/// SharedPreferences-backed store with one lazily resolved client per instance.
///
/// Phase 1 intentionally keeps the legacy backend so existing app keys remain
/// readable. The abstraction permits a later, explicit Async/DataStore
/// migration without changing domain repositories.
final class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore({SharedPreferencesLoader? loader})
    : _loader = loader ?? SharedPreferences.getInstance;

  final SharedPreferencesLoader _loader;
  late final Future<SharedPreferences> _preferences = _loader();

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    final value = (await _preferences).get(key.name);
    if (value is! T) {
      return null;
    }
    if (value is List<String>) {
      return List<String>.unmodifiable(value) as T;
    }
    return value;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async {
    return (await _preferences).containsKey(key.name);
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    final preferences = await _preferences;
    final bool saved;
    if (value is bool) {
      saved = await preferences.setBool(key.name, value);
    } else if (value is int) {
      saved = await preferences.setInt(key.name, value);
    } else if (value is double) {
      saved = await preferences.setDouble(key.name, value);
    } else if (value is String) {
      saved = await preferences.setString(key.name, value);
    } else if (value is List<String>) {
      saved = await preferences.setStringList(key.name, List<String>.of(value));
    } else {
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported preference value for ${key.name}',
      );
    }
    if (!saved) {
      throw StateError('Failed to write preference ${key.name}');
    }
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    final removed = await (await _preferences).remove(key.name);
    if (!removed) {
      throw StateError('Failed to remove preference ${key.name}');
    }
  }
}
