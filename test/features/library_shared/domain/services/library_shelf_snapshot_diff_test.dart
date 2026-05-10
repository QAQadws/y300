import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_snapshot_diff.dart';

void main() {
  test('LibraryShelfSnapshotDiffer reports add remove metadata and order changes', () {
    final differ = LibraryShelfSnapshotDiffer();
    final previous = LibraryShelfSnapshot(
      categories: [_category('default')],
      itemsByCategory: {
        'default': [
          _item('a', title: 'A'),
          _item('b', title: 'B'),
        ],
      },
      visibleMatchCountByCategory: const {'default': 2},
    );
    final next = LibraryShelfSnapshot(
      categories: [_category('default')],
      itemsByCategory: {
        'default': [
          _item('b', title: 'B changed'),
          _item('c', title: 'C'),
        ],
      },
      visibleMatchCountByCategory: const {'default': 2},
    );

    final diff = differ.diff(previous: previous, next: next);

    expect(diff.addedWorkIds, {'c'});
    expect(diff.removedWorkIds, {'a'});
    expect(diff.changedWorkIds, {'b'});
    expect(diff.orderChangedCategoryIds, {'default'});
    expect(diff.hasChanges, isTrue);
  });
}

LibraryCategory _category(String id) {
  return LibraryCategory(
    categoryId: id,
    name: id,
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );
}

LibraryWorkItem _item(String id, {required String title}) {
  return LibraryWorkItem(
    workId: id,
    categoryId: 'default',
    title: title,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );
}
