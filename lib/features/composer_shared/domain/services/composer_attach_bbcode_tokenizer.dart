import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 把 message 中已经成功上传的 `[attach]aid[/attach]` 替换为预览专用标签，
/// 让 BBCode 预览能够渲染本地缓存图片，而不是把原文照搬给用户看。
class ComposerAttachBbCodeTokenizer {
  const ComposerAttachBbCodeTokenizer();

  static const String previewTag = 'y300attach';

  String encodeForPreview(
    String source,
    List<ComposerImageAttachment> imageAttachments,
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
