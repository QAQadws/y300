import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

abstract interface class NovelReaderPreferencesLegacySource {
  Future<NovelReaderPreferences?> load();
}

/// Read-only compatibility bridge for the former global novel SQLite row.
final class SqliteNovelReaderPreferencesLegacySource
    implements NovelReaderPreferencesLegacySource {
  SqliteNovelReaderPreferencesLegacySource(this._dbFutureFactory);

  final Future<Database> Function() _dbFutureFactory;

  @override
  Future<NovelReaderPreferences?> load() async {
    try {
      final db = await _dbFutureFactory();
      final rows = await db.query(
        ComicLocalDb.readerPreferencesTable,
        where: 'content_type = ?',
        whereArgs: const <Object>['novel'],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final row = rows.first;
      final defaults = NovelReaderPreferences.defaults();
      return defaults.copyWith(
        fontSize: _validDouble(
          row['font_size'],
          min: NovelReaderPreferencesSnapshotCodec.minimumFontSize,
          max: NovelReaderPreferencesSnapshotCodec.maximumFontSize,
          fallback: defaults.fontSize,
        ),
        lineHeight: _validDouble(
          row['line_height'],
          min: NovelReaderPreferencesSnapshotCodec.minimumLineHeight,
          max: NovelReaderPreferencesSnapshotCodec.maximumLineHeight,
          fallback: defaults.lineHeight,
        ),
        flowMode: _flowMode(_stringValue(row['flow_mode']), defaults.flowMode),
        themePreset: _themePreset(
          _stringValue(row['theme_preset']) ?? _stringValue(row['theme_mode']),
          defaults.themePreset,
        ),
        conversionMode: _conversionMode(
          _stringValue(row['conversion_mode']),
          defaults.conversionMode,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  double _validDouble(
    Object? raw, {
    required double min,
    required double max,
    required double fallback,
  }) {
    final value = raw is num ? raw.toDouble() : null;
    if (value == null || !value.isFinite || value < min || value > max) {
      return fallback;
    }
    return value;
  }

  String? _stringValue(Object? raw) => raw is String ? raw : null;

  NovelReaderThemePreset _themePreset(
    String? raw,
    NovelReaderThemePreset fallback,
  ) {
    const aliases = <String, NovelReaderThemePreset>{
      'light': NovelReaderThemePreset.light,
      'sepia': NovelReaderThemePreset.sepia,
      'dark': NovelReaderThemePreset.dark,
      'followSystem': NovelReaderThemePreset.followSystem,
      'follow_system': NovelReaderThemePreset.followSystem,
      'system': NovelReaderThemePreset.followSystem,
    };
    return aliases[raw] ?? fallback;
  }

  NovelReaderFlowMode _flowMode(String? raw, NovelReaderFlowMode fallback) {
    return NovelReaderFlowModeCodec.fromStorage(raw, fallback: fallback);
  }

  NovelReaderConversionMode _conversionMode(
    String? raw,
    NovelReaderConversionMode fallback,
  ) {
    for (final value in NovelReaderConversionMode.values) {
      if (value.storageValue == raw) {
        return value;
      }
    }
    return fallback;
  }
}
