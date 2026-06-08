import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyImageAttachmentSorter {
  const ReplyImageAttachmentSorter();

  List<ReplyImageAttachment> sortBySelectionOrder(
    Iterable<ReplyImageAttachment> attachments,
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
