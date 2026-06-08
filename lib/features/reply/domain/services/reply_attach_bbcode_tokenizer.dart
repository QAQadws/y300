import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyAttachBbCodeTokenizer {
  const ReplyAttachBbCodeTokenizer();

  static const String previewTag = 'y300attach';

  String encodeForPreview(
    String source,
    List<ReplyImageAttachment> imageAttachments,
  ) {
    if (source.isEmpty || imageAttachments.isEmpty) {
      return source;
    }
    final validAids = imageAttachments
        .where((attachment) => attachment.canEnterSubmitPayload)
        .map((attachment) => attachment.aid!.trim())
        .where((aid) => aid.isNotEmpty)
        .toSet();
    if (validAids.isEmpty) {
      return source;
    }

    return source.replaceAllMapped(
      RegExp(r'\[attach\]([^\[]+)\[/attach\]', caseSensitive: false),
      (match) {
        final aid = match.group(1)?.trim();
        if (aid == null || !validAids.contains(aid)) {
          return match.group(0)!;
        }
        return '[$previewTag]$aid[/$previewTag]';
      },
    );
  }
}
