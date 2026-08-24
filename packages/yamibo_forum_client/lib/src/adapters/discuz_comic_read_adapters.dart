import '../client/forum_client_config.dart';
import '../contracts/comic_contracts.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/thread_detail_models.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_repository.dart';
import 'forum_image_source_pipeline.dart';

final class DiscuzApiComicEpisodeCatalogRepository
    implements ComicEpisodeCatalogRepository {
  DiscuzApiComicEpisodeCatalogRepository({
    required this.threadRepository,
    required ForumClientConfig config,
  }) : _images = ForumImageSourcePipeline(config);

  final ThreadRepository threadRepository;
  final ForumImageSourcePipeline _images;

  @override
  ComicEpisodeCatalogSourceCapabilities get capabilities =>
      ComicEpisodeCatalogSourceCapabilities(
        _mapCatalogCapabilities(threadRepository.capabilities.values),
      );

  @override
  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadCatalog(ComicEpisodeCatalogRequest request) async {
    final sourceTid = request.sourceTid.trim();
    if (sourceTid.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'comic_episode_source_tid_invalid',
        diagnosticMessage: 'comic_episode_source_tid_invalid',
      );
    }
    final result = await threadRepository.getThreadDetail(
      tid: sourceTid,
      page: 1,
    );
    return result.when(
      success: (data, threadCapabilities, metadata) {
        if (!_supportsCatalog(threadCapabilities)) {
          return const DataReadFailure(
            kind: DataReadFailureKind.unsupported,
            code: 'comic_episode_catalog_capability_unsupported',
            diagnosticMessage: 'comic_episode_catalog_capability_unsupported',
          );
        }
        if (data.tid.trim() != sourceTid) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_episode_source_identity_mismatch',
            diagnosticMessage: 'comic_episode_source_identity_mismatch',
          );
        }
        final firstPosts = data.posts.where(
          (post) => post.isFirst || post.number == 1,
        );
        if (firstPosts.isEmpty) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_episode_first_post_missing',
            diagnosticMessage: 'comic_episode_first_post_missing',
          );
        }
        final references = _images.collectFromPost(firstPosts.first);
        return DataReadSuccess(
          data: ComicEpisodeImageCatalog(
            sourceTid: sourceTid,
            images: references
                .map(
                  (source) => ComicEpisodeImageReference(
                    url: source.normalizedUrl,
                    origin: _mapOrigin(source.origin),
                    attachmentId: source.attachmentId,
                  ),
                )
                .toList(growable: false),
          ),
          capabilities: ComicEpisodeCatalogCapabilities(
            _mapCatalogCapabilities(threadCapabilities.values),
          ),
          metadata: metadata,
        );
      },
      failure: (failure) => failure.retype(),
    );
  }
}

final class ThreadRepositoryComicThreadDiscoveryAdapter
    implements ComicThreadDiscoveryRepository {
  ThreadRepositoryComicThreadDiscoveryAdapter({
    required this.threadRepository,
    required ForumClientConfig config,
  }) : _images = ForumImageSourcePipeline(config);

  final ThreadRepository threadRepository;
  final ForumImageSourcePipeline _images;

  @override
  ComicThreadDiscoverySourceCapabilities get capabilities =>
      ComicThreadDiscoverySourceCapabilities(
        _mapDiscoveryCapabilities(threadRepository.capabilities.values),
      );

  @override
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  load(ComicThreadDiscoveryRequest request) async {
    final sourceTid = request.sourceTid.trim();
    if (sourceTid.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'comic_discovery_source_tid_invalid',
        diagnosticMessage: 'comic_discovery_source_tid_invalid',
      );
    }
    final result = await threadRepository.getThreadDetail(
      tid: sourceTid,
      page: 1,
    );
    return result.when(
      success: (detail, threadCapabilities, metadata) {
        if (!_supportsDiscovery(threadCapabilities)) {
          return const DataReadFailure(
            kind: DataReadFailureKind.unsupported,
            code: 'comic_discovery_capability_unsupported',
            diagnosticMessage: 'comic_discovery_capability_unsupported',
          );
        }
        if (detail.tid.trim() != sourceTid ||
            detail.fid.trim().isEmpty ||
            !_hasValidPosts(detail.posts)) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_discovery_identity_invalid',
            diagnosticMessage: 'comic_discovery_identity_invalid',
          );
        }
        final orderedPosts = detail.posts.toList(growable: false)
          ..sort((left, right) => left.number.compareTo(right.number));
        return DataReadSuccess(
          data: ComicThreadDiscoveryDocument(
            tid: detail.tid.trim(),
            fid: detail.fid.trim(),
            typeId: detail.typeid.trim(),
            subject: detail.subject,
            posts: orderedPosts.map(_mapDiscoveryPost).toList(growable: false),
          ),
          capabilities: ComicThreadDiscoveryCapabilities(
            _mapDiscoveryCapabilities(threadCapabilities.values),
          ),
          metadata: metadata,
        );
      },
      failure: (failure) => failure.retype(),
    );
  }

  ComicThreadDiscoveryPost _mapDiscoveryPost(ThreadPost post) {
    return ComicThreadDiscoveryPost(
      pid: post.pid.trim(),
      authorId: post.authorId.trim(),
      floorNumber: post.number,
      isFirst: post.isFirst,
      messageHtml: post.message,
      imageReferences: _images
          .collectFromPost(post)
          .map(
            (source) => ComicThreadDiscoveryImageReference(
              url: source.normalizedUrl,
              origin: _mapOrigin(source.origin),
              attachmentId: source.attachmentId,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class ApiThreadReplyPageRepository implements ThreadReplyPageRepository {
  const ApiThreadReplyPageRepository({required this.repository});

  final ThreadRepository repository;

  @override
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page}) async {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty || page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'invalid_reply_page_request',
        diagnosticMessage: 'invalid_reply_page_request',
      );
    }
    final result = await repository.getThreadDetail(
      tid: normalizedTid,
      page: page,
    );
    return result.when(
      success: (data, _, metadata) {
        if (data.tid.trim() != normalizedTid || data.currentPage != page) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'reply_page_identity_mismatch',
            diagnosticMessage: 'reply_page_identity_mismatch',
          );
        }
        final seenPids = <String>{};
        final entries = <ThreadReplyEntry>[];
        for (final post in data.posts) {
          final pid = post.pid.trim();
          if (pid.isEmpty || !seenPids.add(pid)) {
            return const DataReadFailure(
              kind: DataReadFailureKind.parse,
              code: 'reply_page_post_identity_invalid',
              diagnosticMessage: 'reply_page_post_identity_invalid',
            );
          }
          entries.add(
            ThreadReplyEntry(
              pid: pid,
              authorId: post.authorId.trim(),
              authorName: post.author.trim(),
              dateline: post.dateline.trim(),
              floorNumber: post.number,
              isFirst: post.isFirst,
              rawMessage: post.message,
            ),
          );
        }
        return DataReadSuccess(
          data: ThreadReplyPage(
            tid: normalizedTid,
            page: data.currentPage,
            perPage: data.perPage,
            replyCount: data.replies,
            posts: List<ThreadReplyEntry>.unmodifiable(entries),
            lastPage: data.lastPage,
            hasNext: data.nextPageUrl != null || data.hasMore,
          ),
          capabilities: _replyPageCapabilities,
          metadata: metadata,
        );
      },
      failure: (failure) => failure.retype(),
    );
  }
}

bool _supportsCatalog(ThreadDetailReadCapabilities capabilities) =>
    const <ThreadDetailCapability>[
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.firstPostIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.renderableBody,
    ].every(capabilities.supports);

bool _supportsDiscovery(ThreadDetailReadCapabilities capabilities) =>
    const <ThreadDetailCapability>[
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.forumIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.firstPostIdentity,
      ThreadDetailCapability.renderableBody,
    ].every(capabilities.supports);

bool _hasValidPosts(List<ThreadPost> posts) {
  if (posts.isEmpty) return false;
  final pids = <String>{};
  return posts.every((post) {
    final pid = post.pid.trim();
    return pid.isNotEmpty && pids.add(pid);
  });
}

ComicEpisodeImageOrigin _mapOrigin(ForumImageSourceOrigin origin) =>
    switch (origin) {
      ForumImageSourceOrigin.dom => ComicEpisodeImageOrigin.dom,
      ForumImageSourceOrigin.attachment => ComicEpisodeImageOrigin.attachment,
    };

DataCapabilitySet<ComicEpisodeCatalogCapability> _mapCatalogCapabilities(
  DataCapabilitySet<ThreadDetailCapability> source,
) => DataCapabilitySet(<ComicEpisodeCatalogCapability, DataCapabilitySupport>{
  ComicEpisodeCatalogCapability.stableSourceIdentity: source.supportOf(
    ThreadDetailCapability.threadIdentity,
  ),
  ComicEpisodeCatalogCapability.reliableFirstPostIdentity: source.supportOf(
    ThreadDetailCapability.firstPostIdentity,
  ),
  ComicEpisodeCatalogCapability.reliableImageOrder: source.supportOf(
    ThreadDetailCapability.orderedPosts,
  ),
  ComicEpisodeCatalogCapability.imageOrigin: source.supportOf(
    ThreadDetailCapability.renderableBody,
  ),
  ComicEpisodeCatalogCapability.attachmentId: source.supportOf(
    ThreadDetailCapability.attachmentMetadata,
  ),
});

DataCapabilitySet<ComicThreadDiscoveryCapability> _mapDiscoveryCapabilities(
  DataCapabilitySet<ThreadDetailCapability> source,
) => DataCapabilitySet(<ComicThreadDiscoveryCapability, DataCapabilitySupport>{
  ComicThreadDiscoveryCapability.stableThreadIdentity: source.supportOf(
    ThreadDetailCapability.threadIdentity,
  ),
  ComicThreadDiscoveryCapability.forumClassification: source.supportOf(
    ThreadDetailCapability.forumIdentity,
  ),
  ComicThreadDiscoveryCapability.orderedPosts: source.supportOf(
    ThreadDetailCapability.orderedPosts,
  ),
  ComicThreadDiscoveryCapability.stablePostIdentity: source.supportOf(
    ThreadDetailCapability.orderedPosts,
  ),
  ComicThreadDiscoveryCapability.reliableFirstPostIdentity: source.supportOf(
    ThreadDetailCapability.firstPostIdentity,
  ),
  ComicThreadDiscoveryCapability.renderableBody: source.supportOf(
    ThreadDetailCapability.renderableBody,
  ),
  ComicThreadDiscoveryCapability.normalizedImageReferences: source.supportOf(
    ThreadDetailCapability.renderableBody,
  ),
  ComicThreadDiscoveryCapability.attachmentIdentity: source.supportOf(
    ThreadDetailCapability.attachmentMetadata,
  ),
});

final _replyPageCapabilities = ThreadReplyPageReadCapabilities(
  DataCapabilitySet<ThreadReplyPageCapability>.supported(
    ThreadReplyPageCapability.values,
  ),
);
