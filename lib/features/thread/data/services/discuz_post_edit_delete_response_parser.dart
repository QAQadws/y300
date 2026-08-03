import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/core/network/discuz_ajax_cdata_parser.dart';

/// Parses the integer CDATA payload returned by Discuz deleteattach.
final class DiscuzPostEditDeleteResponseParser {
  const DiscuzPostEditDeleteResponseParser({
    this.cdataParser = const DiscuzAjaxCdataParser(),
  });

  final DiscuzAjaxCdataParser cdataParser;

  PostEditAttachmentDeleteResult parse({
    required String body,
    required String aid,
  }) {
    final count = cdataParser.extractInteger(body);
    if (count == null) {
      return PostEditAttachmentDeleteResult(
        aid: aid,
        outcome: PostEditAttachmentDeleteOutcome.unconfirmed,
      );
    }
    return PostEditAttachmentDeleteResult(
      aid: aid,
      deletedCount: count,
      outcome: count > 0
          ? PostEditAttachmentDeleteOutcome.deleted
          : PostEditAttachmentDeleteOutcome.notDeleted,
    );
  }
}
