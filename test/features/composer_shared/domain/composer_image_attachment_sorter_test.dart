import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_sorter.dart';

void main() {
  group('ComposerImageAttachmentSorter', () {
    const sorter = ComposerImageAttachmentSorter();

    ComposerImageAttachment attachment({
      required String localId,
      required int order,
    }) {
      return ComposerImageAttachment(
        localId: localId,
        localPath: '/gallery/$localId.jpg',
        fileName: '$localId.jpg',
        mimeType: 'image/jpeg',
        order: order,
        status: ComposerImageAttachmentStatus.local,
      );
    }

    test('sorts by order', () {
      final sorted = sorter.sortBySelectionOrder([
        attachment(localId: 'c', order: 2),
        attachment(localId: 'a', order: 0),
        attachment(localId: 'b', order: 1),
      ]);

      expect(sorted.map((item) => item.localId), ['a', 'b', 'c']);
    });

    test('uses localId as stable fallback for same order', () {
      final sorted = sorter.sortBySelectionOrder([
        attachment(localId: 'b', order: 0),
        attachment(localId: 'a', order: 0),
      ]);

      expect(sorted.map((item) => item.localId), ['a', 'b']);
    });

    test('does not mutate original list', () {
      final original = [
        attachment(localId: 'b', order: 1),
        attachment(localId: 'a', order: 0),
      ];

      final sorted = sorter.sortBySelectionOrder(original);

      expect(original.map((item) => item.localId), ['b', 'a']);
      expect(sorted.map((item) => item.localId), ['a', 'b']);
    });
  });
}
