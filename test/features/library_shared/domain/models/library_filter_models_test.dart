import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';

void main() {
  group('LibraryFilterSet', () {
    test('defaults should be default state', () {
      const filters = LibraryFilterSet.defaults;
      expect(filters.isDefault, isTrue);
    });

    test('copyWith should update one field only', () {
      const filters = LibraryFilterSet.defaults;
      final updated = filters.copyWith(unread: TriStateFilterValue.include);
      expect(updated.unread, TriStateFilterValue.include);
      expect(updated.downloaded, TriStateFilterValue.ignore);
      expect(updated.isDefault, isFalse);
    });
  });
}
