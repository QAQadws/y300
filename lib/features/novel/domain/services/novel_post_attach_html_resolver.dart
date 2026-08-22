import 'dart:convert';

import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

class NovelPostAttachHtmlResolver {
  const NovelPostAttachHtmlResolver({
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
  }) : _imageSourcePipeline = imageSourcePipeline;

  final ForumImageSourcePipeline _imageSourcePipeline;

  String resolve(ThreadPost post) {
    if (post.attachmentImages.isEmpty) {
      return post.message;
    }
    final sources = _imageSourcePipeline.collectFromPost(post);
    final aidToUrl = <String, String>{
      for (final source in sources)
        if (source.aid?.trim().isNotEmpty == true)
          source.aid!.trim(): source.normalizedUrl,
    };
    if (aidToUrl.isEmpty) {
      return post.message;
    }
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    return post.message.replaceAllMapped(
      RegExp(r'\[attach\](\d+)\[/attach\]', caseSensitive: false),
      (match) {
        final url = aidToUrl[match.group(1)];
        return url == null
            ? match.group(0)!
            : '<img src="${escape.convert(url)}">';
      },
    );
  }
}
