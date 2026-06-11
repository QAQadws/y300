import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 按用户在选择器中的拾取顺序（[ComposerImageAttachment.order]）排序，
/// 同 order 时退化到 localId，保证排序结果在测试中稳定。
class ComposerImageAttachmentSorter {
  const ComposerImageAttachmentSorter();

  List<ComposerImageAttachment> sortBySelectionOrder(
    Iterable<ComposerImageAttachment> attachments,
  ) {
    final sorted = attachments.toList(growable: false);
    sorted.sort((a, b) {
      final orderComparison = a.order.compareTo(b.order);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return a.localId.compareTo(b.localId);
    });
    return sorted;
  }
}
