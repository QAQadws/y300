import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_snapshot_codec.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';

void main() {
  const codec = LibraryViewPreferencesSnapshotCodec();
  final defaults = LibraryShelfViewPreferences.defaults(
    moduleKey: LibraryModuleKey.novel,
    displayMode: LibraryDisplayMode.list,
    sortOption: const LibraryShelfSortOption(
      field: LibraryShelfSortField.favoriteAddedAt,
      direction: LibrarySortDirection.asc,
    ),
  );

  test('v1 shelf snapshot round-trips every persistent field', () {
    final source = LibraryShelfViewPreferences(
      moduleKey: LibraryModuleKey.novel,
      displayMode: LibraryDisplayMode.grid,
      gridColumnCount: 4,
      sortOption: const LibraryShelfSortOption(
        field: LibraryShelfSortField.chapterCount,
        direction: LibrarySortDirection.desc,
      ),
      filters: const LibraryFilterSet(bookmarked: TriStateFilterValue.include),
      lastCategoryId: 'favorites',
    );

    final encoded = codec.encode(source, defaults: defaults);
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final decoded = codec.decode(encoded, defaults: defaults);

    expect(json['schemaVersion'], 1);
    expect(json['moduleKey'], 'novel');
    expect(decoded, source);
  });

  test('invalid fields fall back independently and columns are clamped', () {
    final decoded = codec.decode(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'moduleKey': 'novel',
        'displayMode': 'future-mode',
        'gridColumnCount': 99,
        'sort': <String, Object>{
          'field': 'chapterCount',
          'direction': 'future-direction',
        },
        'filters': <String, Object>{
          'downloaded': 'include',
          'bookmarked': 'future-filter',
        },
        'lastCategoryId': '  category-1  ',
      }),
      defaults: defaults,
    );

    expect(decoded.displayMode, LibraryDisplayMode.list);
    expect(decoded.gridColumnCount, 10);
    expect(decoded.sortOption.field, LibraryShelfSortField.chapterCount);
    expect(decoded.sortOption.direction, LibrarySortDirection.asc);
    expect(decoded.filters.downloaded, TriStateFilterValue.include);
    expect(decoded.filters.bookmarked, TriStateFilterValue.ignore);
    expect(decoded.lastCategoryId, 'category-1');
  });

  test('malformed, unsupported, and wrong-module snapshots use defaults', () {
    for (final source in <String>[
      '{broken',
      '[]',
      jsonEncode(<String, Object>{'schemaVersion': 2, 'moduleKey': 'novel'}),
      jsonEncode(<String, Object>{'schemaVersion': 1, 'moduleKey': 'comic'}),
    ]) {
      expect(codec.decode(source, defaults: defaults), defaults);
    }
  });
}
