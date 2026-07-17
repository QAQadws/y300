import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';

void main() {
  test('default shelf sort should be favoriteAddedAt desc', () {
    const defaults = LibraryShelfSortOption.defaults;
    expect(defaults.field, LibraryShelfSortField.favoriteAddedAt);
    expect(defaults.direction, LibrarySortDirection.desc);
  });

  test('default shelf sort places the newest favorite first', () {
    final items = LibraryShelfQueryUtils.filterAndSort(
      source: <LibraryWorkItem>[
        _item('older', DateTime(2026, 1, 1)),
        _item('newer', DateTime(2026, 7, 1)),
      ],
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: '',
    );

    expect(items.map((item) => item.workId), <String>['newer', 'older']);
  });

  test('public shelf exposes three sort fields in display order', () {
    expect(LibraryShelfSortOption.availableFields, <LibraryShelfSortField>[
      LibraryShelfSortField.chapterCount,
      LibraryShelfSortField.unreadCount,
      LibraryShelfSortField.favoriteAddedAt,
    ]);
  });

  test('unsupported public shelf sort falls back to defaults', () {
    const unsupported = LibraryShelfSortOption(
      field: LibraryShelfSortField.name,
      direction: LibrarySortDirection.desc,
    );

    final normalized = LibraryShelfSortOption.normalize(unsupported);

    expect(normalized.field, LibraryShelfSortField.favoriteAddedAt);
    expect(normalized.direction, LibrarySortDirection.desc);
  });

  test('copyWith should update direction', () {
    const defaults = LibraryShelfSortOption.defaults;
    final updated = defaults.copyWith(direction: LibrarySortDirection.asc);
    expect(updated.direction, LibrarySortDirection.asc);
    expect(updated.field, defaults.field);
  });

  test('detail source sorting defaults to ascending', () {
    expect(
      LibraryChapterSortOption.defaults.direction,
      LibrarySortDirection.asc,
    );
  });
}

LibraryWorkItem _item(String workId, DateTime addedAt) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: 'default',
    title: workId,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: addedAt,
  );
}
