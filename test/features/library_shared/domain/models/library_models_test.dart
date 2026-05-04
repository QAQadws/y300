import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  group('LibraryCategory', () {
    test('isDefault should be true when categoryId is default', () {
      final category = LibraryCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(category.isDefault, isTrue);
    });

    test('copyWith should override visibleMatchCount', () {
      final category = LibraryCategory(
        categoryId: 'c1',
        name: '分类',
        sortOrder: 1,
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = category.copyWith(visibleMatchCount: 6);
      expect(updated.visibleMatchCount, 6);
      expect(updated.categoryId, category.categoryId);
    });
  });
}
