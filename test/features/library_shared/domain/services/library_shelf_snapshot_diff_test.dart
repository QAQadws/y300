import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_snapshot_diff.dart';

void main() {
  test(
    'LibraryShelfSnapshotDiffer reports add remove metadata and order changes',
    () {
      final differ = LibraryShelfSnapshotDiffer();
      final previous = LibraryShelfSnapshot(
        categories: [_category('default')],
        itemsByCategory: {
          'default': [_item('a', title: 'A'), _item('b', title: 'B')],
        },
        visibleMatchCountByCategory: const {'default': 2},
      );
      final next = LibraryShelfSnapshot(
        categories: [_category('default')],
        itemsByCategory: {
          'default': [_item('b', title: 'B changed'), _item('c', title: 'C')],
        },
        visibleMatchCountByCategory: const {'default': 2},
      );

      final diff = differ.diff(previous: previous, next: next);

      expect(diff.addedWorkIds, {'c'});
      expect(diff.removedWorkIds, {'a'});
      expect(diff.changedWorkIds, {'b'});
      expect(diff.orderChangedCategoryIds, {'default'});
      expect(diff.hasChanges, isTrue);
    },
  );

  test('LibraryShelfSnapshotDiffer reports custom cover focus changes', () {
    const differ = LibraryShelfSnapshotDiffer();
    final previous = LibraryShelfSnapshot(
      categories: [_category('default')],
      itemsByCategory: {
        'default': [
          _item('a', title: 'A', customCoverFocusX: 0, customCoverFocusY: 0),
        ],
      },
      visibleMatchCountByCategory: const {'default': 1},
    );
    final next = LibraryShelfSnapshot(
      categories: [_category('default')],
      itemsByCategory: {
        'default': [
          _item(
            'a',
            title: 'A',
            customCoverFocusX: 0.75,
            customCoverFocusY: -0.5,
          ),
        ],
      },
      visibleMatchCountByCategory: const {'default': 1},
    );

    final diff = differ.diff(previous: previous, next: next);

    expect(diff.changedWorkIds, {'a'});
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

LibraryWorkItem _item(
  String id, {
  required String title,
  double? customCoverFocusX,
  double? customCoverFocusY,
}) {
  return LibraryWorkItem(
    workId: id,
    categoryId: 'default',
    title: title,
    customCoverFocusX: customCoverFocusX,
    customCoverFocusY: customCoverFocusY,
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );
}
