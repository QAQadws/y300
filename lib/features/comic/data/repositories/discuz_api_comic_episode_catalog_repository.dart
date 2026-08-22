import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_episode_image_catalog.dart';
import 'package:y300/features/comic/domain/repositories/comic_episode_catalog_repository.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

final class DiscuzApiComicEpisodeCatalogRepository
    implements ComicEpisodeCatalogRepository {
  DiscuzApiComicEpisodeCatalogRepository({
    required ThreadRepository threadRepository,
    required ForumImageSourcePipeline imageSourcePipeline,
  }) : _threadRepository = threadRepository,
       _imageSourcePipeline = imageSourcePipeline;

  final ThreadRepository _threadRepository;
  final ForumImageSourcePipeline _imageSourcePipeline;

  @override
  ComicEpisodeCatalogSourceCapabilities get capabilities =>
      _sourceCapabilities;

  @override
  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  > loadCatalog(ComicEpisodeCatalogRequest request) async {
    final sourceTid = request.sourceTid.trim();
    if (sourceTid.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'comic_episode_source_tid_invalid',
        diagnosticMessage: 'Comic episode source identity is empty.',
      );
    }
    final result = await _threadRepository.getThreadDetail(
      tid: sourceTid,
      page: 1,
    );
    return result.when(
      success: (data, _, metadata) {
        final firstPosts = data.posts.where(
          (post) => post.isFirst || post.number == 1,
        );
        if (firstPosts.isEmpty) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_episode_first_post_missing',
            diagnosticMessage: 'The source did not identify the first post.',
          );
        }
        try {
          final sources = _imageSourcePipeline.collectFromPost(firstPosts.first);
          final images = sources
              .map(
                (source) => ComicEpisodeImageReference(
                  url: source.normalizedUrl,
                  origin: switch (source.origin) {
                    ForumImageSourceOrigin.dom => ComicEpisodeImageOrigin.dom,
                    ForumImageSourceOrigin.attachment =>
                      ComicEpisodeImageOrigin.attachment,
                  },
                  attachmentId: source.aid,
                ),
              )
              .toList(growable: false);
          return DataReadSuccess(
            data: ComicEpisodeImageCatalog(
              sourceTid: sourceTid,
              images: images,
            ),
            capabilities: capabilities.toReadCapabilities(),
            metadata: metadata,
          );
        } catch (error) {
          return DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_episode_image_catalog_parse_failed',
            diagnosticMessage: 'Comic episode image extraction failed: $error',
          );
        }
      },
      failure: (failure) => DataReadFailure(
        kind: failure.kind,
        code: failure.code,
        statusCode: failure.statusCode,
        diagnosticMessage: failure.diagnosticMessage,
      ),
    );
  }
}

final _sourceCapabilities = ComicEpisodeCatalogSourceCapabilities(
  DataCapabilitySet<ComicEpisodeCatalogCapability>.supported(
    ComicEpisodeCatalogCapability.values,
  ),
);
