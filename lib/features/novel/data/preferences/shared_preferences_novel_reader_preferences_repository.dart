import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';

import 'novel_reader_work_preferences_codec.dart';

final class SharedPreferencesNovelReaderPreferencesRepository
    implements NovelReaderScopedPreferencesRepository {
  SharedPreferencesNovelReaderPreferencesRepository({
    required PreferencesStore preferencesStore,
    required NovelReaderPreferencesLegacySource legacySource,
    NovelReaderPreferencesSnapshotCodec codec =
        const NovelReaderPreferencesSnapshotCodec(),
  }) : _preferencesStore = preferencesStore,
       _legacySource = legacySource,
       _codec = codec,
       _workCodec = NovelReaderWorkPreferencesCodec(codec);

  static const int migrationVersion = 1;

  final PreferencesStore _preferencesStore;
  final NovelReaderPreferencesLegacySource _legacySource;
  final NovelReaderPreferencesSnapshotCodec _codec;
  final NovelReaderWorkPreferencesCodec _workCodec;
  Future<void> _tail = Future<void>.value();

  @override
  Future<NovelReaderPreferences> load() => _serialized(_loadDefaults);

  Future<NovelReaderPreferences> _loadDefaults() async {
    if (await _preferencesStore.contains(
      PreferenceKeys.novelReaderSnapshotV1,
    )) {
      return _codec.decode(
        await _preferencesStore.read(PreferenceKeys.novelReaderSnapshotV1),
      );
    }

    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.novelReaderMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return NovelReaderPreferences.defaults();
    }

    NovelReaderPreferences? legacy;
    try {
      legacy = await _legacySource.load();
    } catch (_) {
      legacy = null;
    }
    final migrated = _codec.normalize(
      legacy ?? NovelReaderPreferences.defaults(),
    );
    await _write(migrated);
    return migrated;
  }

  @override
  Future<void> save(NovelReaderPreferences preferences) =>
      _serialized(() => _write(preferences));

  @override
  Future<NovelReaderPreferenceScopes> loadScopes(String novelId) =>
      _serialized(() async {
        final defaults = await _loadDefaults();
        final work = await _readWork(_workKey(novelId));
        return _workCodec.scope(defaults, work.record);
      });

  @override
  Future<NovelReaderPreferenceScopes> saveScope(
    String novelId, {
    required NovelReaderPreferenceScope scope,
    required NovelReaderPreferences previous,
    required NovelReaderPreferences next,
  }) => _serialized(() async {
    final key = _workKey(novelId);
    final work = await _readWork(key);
    final defaults = await _loadDefaults();
    final changes = _workCodec.changes(previous, next);
    if (changes.isEmpty) return _workCodec.scope(defaults, work.record);
    if (scope == NovelReaderPreferenceScope.defaults) {
      final updated = _workCodec.apply(defaults, changes);
      await _write(updated);
      return _workCodec.scope(updated, work.record);
    }
    final source = _workCodec.encode(work.record, changes);
    await _writeWork(key, previous: work.source, next: source);
    return _workCodec.scope(defaults, _workCodec.decode(source));
  });

  @override
  Future<NovelReaderPreferenceScopes> resetWork(String novelId) =>
      _serialized(() async {
        final key = _workKey(novelId);
        final work = await _readWork(key);
        final defaults = await _loadDefaults();
        final source = _workCodec.encode(work.record, const {}, reset: true);
        await _writeWork(key, previous: work.source, next: source);
        return _workCodec.scope(defaults, _workCodec.decode(source));
      });

  Future<({String? source, NovelReaderWorkPreferenceRecord record})> _readWork(
    PreferenceKey<String> key,
  ) async {
    final source = await _preferencesStore.read(key);
    final record = source == null && await _preferencesStore.contains(key)
        ? const NovelReaderWorkPreferenceRecord.unsupported()
        : _workCodec.decode(source);
    return (source: source, record: record);
  }

  Future<void> _writeWork(
    PreferenceKey<String> key, {
    required String? previous,
    required String? next,
  }) async {
    if (previous == next) return;
    if (next == null) {
      await _preferencesStore.remove(key);
    } else {
      await _preferencesStore.write(key, next);
    }
  }

  static PreferenceKey<String> _workKey(String novelId) {
    if (novelId.isEmpty) throw ArgumentError('Missing novel identity');
    final digest = sha256.convert(utf8.encode(novelId));
    return PreferenceKey<String>('reader.novel.work.v1.$digest');
  }

  // The production provider shares one repository for all reader owners. A
  // work patch always merges with its latest stored scope inside this queue.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _write(NovelReaderPreferences preferences) async {
    // Recheck at the write boundary, including saves before load and snapshots
    // upgraded since this repository last loaded. Never cache a writable flag.
    final previous = await _preferencesStore.read(
      PreferenceKeys.novelReaderSnapshotV1,
    );
    final encoded = _codec.encode(preferences, previousSource: previous);
    await _preferencesStore.write(
      PreferenceKeys.novelReaderSnapshotV1,
      encoded,
    );
    await _preferencesStore.write(
      PreferenceKeys.novelReaderMigrationVersion,
      migrationVersion,
    );
  }
}
