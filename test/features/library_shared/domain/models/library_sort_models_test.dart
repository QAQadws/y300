import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

void main() {
  test('default shelf sort should be favoriteAddedAt desc', () {
    const defaults = LibraryShelfSortOption.defaults;
    expect(defaults.field, LibraryShelfSortField.favoriteAddedAt);
    expect(defaults.direction, LibrarySortDirection.desc);
  });

  test('copyWith should update direction', () {
    const defaults = LibraryShelfSortOption.defaults;
    final updated = defaults.copyWith(direction: LibrarySortDirection.asc);
    expect(updated.direction, LibrarySortDirection.asc);
    expect(updated.field, defaults.field);
  });
}

