import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

/// One bounded copy of the last home snapshot, using the same codec and scoped
/// key as SQLite. Startup can read it without opening the library database.
final class ForumHomeSnapshotMirror {
  ForumHomeSnapshotMirror({SharedPreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final SharedPreferencesLoader _preferencesLoader;
  Future<void> _mutations = Future<void>.value();
  int _generation = 0;
  bool _invalidating = false;

  int get generation => _generation;
  static const _maxBytes = 256 * 1024;

  Future<Map<String, Object?>?> read({String? cacheKey}) async {
    final generation = _generation;
    try {
      final raw = (await _preferencesLoader()).getString(
        TechnicalStorageKeys.forumHomeStartupSnapshotV1,
      );
      if (raw == null ||
          _invalidating ||
          generation != _generation ||
          utf8.encode(raw).length > _maxBytes) {
        return null;
      }
      final row = Map<String, Object?>.from(jsonDecode(raw) as Map);
      return cacheKey == null || row['cache_key'] == cacheKey ? row : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    Map<String, Object?> row, {
    required int generation,
    required bool Function() isCurrent,
  }) {
    return _enqueue(() async {
      final preferences = await _preferencesLoader();
      if (generation != _generation || !isCurrent()) return;
      final raw = jsonEncode(row);
      if (utf8.encode(raw).length > _maxBytes) {
        await preferences.remove(
          TechnicalStorageKeys.forumHomeStartupSnapshotV1,
        );
        return;
      }
      await preferences.setString(
        TechnicalStorageKeys.forumHomeStartupSnapshotV1,
        raw,
      );
      if (generation == _generation) _invalidating = false;
    });
  }

  Future<void> deleteOwner(
    String ownerType,
    String ownerId, {
    bool prefix = false,
  }) {
    if (ownerType != 'forum' ||
        !(prefix ? 'home'.startsWith(ownerId) : ownerId == 'home')) {
      return Future<void>.value();
    }
    // Retire already queued writes before waiting on any local storage.
    final generation = ++_generation;
    _invalidating = true;
    return _enqueue(() async {
      var removed = false;
      try {
        await (await _preferencesLoader()).remove(
          TechnicalStorageKeys.forumHomeStartupSnapshotV1,
        );
        removed = true;
      } finally {
        if (generation == _generation) _invalidating = !removed;
      }
    });
  }

  Future<int> bytes() async {
    try {
      final raw = (await _preferencesLoader()).getString(
        TechnicalStorageKeys.forumHomeStartupSnapshotV1,
      );
      return raw == null ? 0 : utf8.encode(raw).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _enqueue(Future<void> Function() mutation) {
    final operation = _mutations.then((_) => mutation());
    // A damaged mirror is a cache miss and cannot poison later refreshes.
    _mutations = operation.catchError((Object _) {});
    return _mutations;
  }
}
