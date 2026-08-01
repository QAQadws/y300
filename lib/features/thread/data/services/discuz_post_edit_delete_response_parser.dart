import 'package:y300/features/thread/domain/models/post_edit_models.dart';

/// Parses the integer CDATA payload returned by Discuz deleteattach.
final class DiscuzPostEditDeleteResponseParser {
  const DiscuzPostEditDeleteResponseParser();

  PostEditAttachmentDeleteResult parse({
    required String body,
    required String aid,
  }) {
    final cdata = _extractCdata(body);
    final count = cdata == null ? null : int.tryParse(cdata.trim());
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

  String? _extractCdata(String body) {
    final start = body.indexOf('<![CDATA[');
    if (start < 0) {
      return null;
    }
    final contentStart = start + '<![CDATA['.length;
    final end = body.indexOf(']]>', contentStart);
    if (end < 0) {
      return null;
    }
    return body.substring(contentStart, end);
  }
}
