import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/services/novel_first_post_catalog_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_intro_section_extractor.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

abstract interface class NovelSourceMetadataParser {
  NovelSourceMetadata parseFirstPost({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime ingestedAt,
  });
}

class DefaultNovelSourceMetadataParser implements NovelSourceMetadataParser {
  const DefaultNovelSourceMetadataParser({
    NovelFirstPostCatalogExtractor catalogExtractor =
        const NovelFirstPostCatalogExtractor(),
    NovelIntroSectionExtractor introExtractor =
        const DefaultNovelIntroSectionExtractor(),
    ForumPostImageSourceCollector imageSourceCollector =
        const ForumPostImageSourceCollector(),
  }) : _catalogExtractor = catalogExtractor,
       _introExtractor = introExtractor,
       _imageSourceCollector = imageSourceCollector;

  static const int favoriteDetailSourceVersion = 4;

  final NovelFirstPostCatalogExtractor _catalogExtractor;
  final NovelIntroSectionExtractor _introExtractor;
  final ForumPostImageSourceCollector _imageSourceCollector;

  @override
  NovelSourceMetadata parseFirstPost({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime ingestedAt,
  }) {
    final tid = _requireNumericId(seed.tid, 'seed.tid');
    final detailTid = detail.tid.trim();
    if (detailTid.isNotEmpty && detailTid != tid) {
      throw StateError(
        'Novel source detail tid does not match its seed: $detailTid != $tid',
      );
    }
    final fid = _requireText(
      seed.fid.trim().isEmpty ? detail.fid : seed.fid,
      'seed.fid',
    );
    if (detail.posts.isEmpty) {
      throw const FormatException('Novel source detail has no first post.');
    }

    // This is the sole post-list access in the metadata parser. In particular,
    // do not sort, scan, or validate version=4 later posts.
    final firstPost = detail.posts.first;
    final firstPostPid = _requireNumericId(firstPost.pid, 'firstPost.pid');
    final publisherId = _requireNumericId(
      firstPost.authorId,
      'firstPost.authorId',
    );
    final imageUrls = _imageSourceCollector.collect(firstPost);

    return NovelSourceMetadata(
      novelId: 'novel:$fid:$tid',
      tid: tid,
      fid: fid,
      subject: detail.subject.trim(),
      publisherName: firstPost.author.trim(),
      publisherId: publisherId,
      firstPostPid: firstPostPid,
      catalogEntries: _catalogExtractor.extract(
        threadTid: tid,
        firstPost: firstPost,
      ),
      sourceIntro: _introExtractor.extract(firstPostHtml: firstPost.message),
      coverImageUrl: imageUrls.isEmpty ? null : imageUrls.first,
      sourceApiVersion: favoriteDetailSourceVersion,
      ingestedAt: ingestedAt,
    );
  }

  String _requireNumericId(String value, String name) {
    final normalized = value.trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(normalized)) {
      throw FormatException('$name must be a positive numeric id.');
    }
    return normalized;
  }

  String _requireText(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw FormatException('$name must not be empty.');
    }
    return normalized;
  }
}
