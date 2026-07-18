import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class LegacyLibraryDisplayPreferences {
  const LegacyLibraryDisplayPreferences({
    required this.displayMode,
    required this.gridColumnCount,
  });

  final LibraryDisplayMode displayMode;
  final int gridColumnCount;
}

abstract interface class LibraryViewPreferencesLegacySource {
  Future<LegacyLibraryDisplayPreferences?> loadDisplayPreferences({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
    required int defaultGridColumnCount,
  });
}

/// Read-only bridge retained for one compatibility window.
///
/// A concrete row in `library_display_settings` always wins, including an
/// explicit three-column value. The old comic setting is consulted only when
/// that row is absent.
final class SqliteLibraryViewPreferencesLegacySource
    implements LibraryViewPreferencesLegacySource {
  SqliteLibraryViewPreferencesLegacySource(this._dbFuture);

  final Future<Database> _dbFuture;

  @override
  Future<LegacyLibraryDisplayPreferences?> loadDisplayPreferences({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
    required int defaultGridColumnCount,
  }) async {
    final db = await _dbFuture;
    final shared = await _loadSharedDisplayRow(
      db,
      moduleKey: moduleKey,
      defaultDisplayMode: defaultDisplayMode,
      defaultGridColumnCount: defaultGridColumnCount,
    );
    if (shared != null) {
      return shared;
    }
    if (moduleKey != LibraryModuleKey.comic) {
      return null;
    }
    final oldColumns = await _loadLegacyComicGridColumns(db);
    if (oldColumns == null) {
      return null;
    }
    return LegacyLibraryDisplayPreferences(
      displayMode: defaultDisplayMode,
      gridColumnCount: _normalizeGridColumns(
        oldColumns,
        fallback: defaultGridColumnCount,
      ),
    );
  }

  Future<LegacyLibraryDisplayPreferences?> _loadSharedDisplayRow(
    Database db, {
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
    required int defaultGridColumnCount,
  }) async {
    try {
      final rows = await db.query(
        ComicLocalDb.libraryDisplaySettingsTable,
        columns: const <String>['display_mode', 'grid_columns'],
        where: 'module_key = ?',
        whereArgs: <Object>[_moduleKeyValue(moduleKey)],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final row = rows.first;
      return LegacyLibraryDisplayPreferences(
        displayMode: _parseDisplayMode(
          row['display_mode'],
          fallback: defaultDisplayMode,
        ),
        gridColumnCount: _normalizeGridColumns(
          row['grid_columns'],
          fallback: defaultGridColumnCount,
        ),
      );
    } on DatabaseException {
      return null;
    }
  }

  Future<Object?> _loadLegacyComicGridColumns(Database db) async {
    try {
      final rows = await db.query(
        ComicLocalDb.settingsTable,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>['grid_column_count'],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['value'];
    } on DatabaseException {
      return null;
    }
  }

  LibraryDisplayMode _parseDisplayMode(
    Object? raw, {
    required LibraryDisplayMode fallback,
  }) {
    return switch (raw) {
      'grid' => LibraryDisplayMode.grid,
      'list' => LibraryDisplayMode.list,
      _ => fallback,
    };
  }

  int _normalizeGridColumns(Object? raw, {required int fallback}) {
    final parsed = switch (raw) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };
    return (parsed ?? fallback).clamp(1, 10).toInt();
  }

  String _moduleKeyValue(LibraryModuleKey moduleKey) {
    return switch (moduleKey) {
      LibraryModuleKey.comic => 'comic',
      LibraryModuleKey.novel => 'novel',
      LibraryModuleKey.favorite => 'favorite',
    };
  }
}
