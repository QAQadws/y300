import 'dart:convert';

import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';

final class LibraryViewPreferencesSnapshotCodec {
  const LibraryViewPreferencesSnapshotCodec();

  static const int schemaVersion = 1;

  String encode(
    LibraryShelfViewPreferences preferences, {
    required LibraryShelfViewPreferences defaults,
  }) {
    final normalized = normalize(preferences, defaults: defaults);
    return jsonEncode(<String, Object?>{
      'schemaVersion': schemaVersion,
      'moduleKey': normalized.moduleKey.name,
      'displayMode': normalized.displayMode.name,
      'gridColumnCount': normalized.gridColumnCount,
      'sort': <String, Object>{
        'field': normalized.sortOption.field.name,
        'direction': normalized.sortOption.direction.name,
      },
      'filters': <String, Object>{
        'downloaded': normalized.filters.downloaded.name,
        'unread': normalized.filters.unread.name,
        'read': normalized.filters.read.name,
        'hasTags': normalized.filters.hasTags.name,
        'bookmarked': normalized.filters.bookmarked.name,
      },
      'lastCategoryId': normalized.lastCategoryId,
    });
  }

  LibraryShelfViewPreferences decode(
    String? source, {
    required LibraryShelfViewPreferences defaults,
  }) {
    if (source == null || source.trim().isEmpty) {
      return defaults;
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion ||
          decoded['moduleKey'] != defaults.moduleKey.name) {
        return defaults;
      }
      final sort = _mapOrEmpty(decoded['sort']);
      final filters = _mapOrEmpty(decoded['filters']);
      return normalize(
        LibraryShelfViewPreferences(
          moduleKey: defaults.moduleKey,
          displayMode: _enumByName(
            decoded['displayMode'],
            LibraryDisplayMode.values,
            defaults.displayMode,
          ),
          gridColumnCount: decoded['gridColumnCount'] is int
              ? decoded['gridColumnCount'] as int
              : defaults.gridColumnCount,
          sortOption: LibraryShelfSortOption(
            field: _enumByName(
              sort['field'],
              LibraryShelfSortField.values,
              defaults.sortOption.field,
            ),
            direction: _enumByName(
              sort['direction'],
              LibrarySortDirection.values,
              defaults.sortOption.direction,
            ),
          ),
          filters: LibraryFilterSet(
            downloaded: _filterValue(
              filters['downloaded'],
              defaults.filters.downloaded,
            ),
            unread: _filterValue(filters['unread'], defaults.filters.unread),
            read: _filterValue(filters['read'], defaults.filters.read),
            hasTags: _filterValue(filters['hasTags'], defaults.filters.hasTags),
            bookmarked: _filterValue(
              filters['bookmarked'],
              defaults.filters.bookmarked,
            ),
          ),
          lastCategoryId: decoded['lastCategoryId'] is String
              ? decoded['lastCategoryId'] as String
              : null,
        ),
        defaults: defaults,
      );
    } on FormatException {
      return defaults;
    }
  }

  LibraryShelfViewPreferences normalize(
    LibraryShelfViewPreferences preferences, {
    required LibraryShelfViewPreferences defaults,
  }) {
    if (preferences.moduleKey != defaults.moduleKey) {
      return defaults;
    }
    final rawCategoryId = preferences.lastCategoryId?.trim();
    return LibraryShelfViewPreferences(
      moduleKey: defaults.moduleKey,
      displayMode: preferences.displayMode,
      gridColumnCount: preferences.gridColumnCount.clamp(1, 10).toInt(),
      sortOption: preferences.sortOption,
      filters: preferences.filters,
      lastCategoryId: rawCategoryId == null || rawCategoryId.isEmpty
          ? null
          : rawCategoryId,
    );
  }

  Map<String, dynamic> _mapOrEmpty(Object? value) {
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  TriStateFilterValue _filterValue(Object? raw, TriStateFilterValue fallback) {
    return _enumByName(raw, TriStateFilterValue.values, fallback);
  }

  T _enumByName<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) {
          return value;
        }
      }
    }
    return fallback;
  }
}
