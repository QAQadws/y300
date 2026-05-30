import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

/// Extracts image URLs from Discuz mobile-api attachment metadata.
///
/// Some older comic posts keep the real pages only in `postlist.attachments`.
/// Keeping this separate from DOM parsing makes the source of each image clear
/// and lets all comic parsing paths share the same attachment URL rules.
class ForumAttachmentImageExtractor {
  const ForumAttachmentImageExtractor({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  List<String> extractImageUrls(ThreadPost post) {
    return DefaultForumImageSourcePipeline.extractAttachmentSources(
      post,
      urlResolver: _urlResolver,
    ).map((source) => source.normalizedUrl).toList(growable: false);
  }
}
