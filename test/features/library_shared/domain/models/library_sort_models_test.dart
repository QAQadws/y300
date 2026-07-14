import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

void main() {
  test('default shelf sort should be favoriteAddedAt asc', () {
    const defaults = LibraryShelfSortOption.defaults;
    expect(defaults.field, LibraryShelfSortField.favoriteAddedAt);
    expect(defaults.direction, LibrarySortDirection.asc);
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
    expect(normalized.direction, LibrarySortDirection.asc);
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
