import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/data/mappers/comic_thread_discovery_document_mapper.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_thread_discovery_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

final class ThreadRepositoryComicThreadDiscoveryAdapter
    implements ComicThreadDiscoveryRepository {
  const ThreadRepositoryComicThreadDiscoveryAdapter({
    required ThreadRepository threadRepository,
    ComicThreadDiscoveryDocumentMapper mapper =
        const ComicThreadDiscoveryDocumentMapper(),
  }) : _threadRepository = threadRepository,
       _mapper = mapper;

  final ThreadRepository _threadRepository;
  final ComicThreadDiscoveryDocumentMapper _mapper;

  @override
  ComicThreadDiscoverySourceCapabilities get capabilities =>
      ComicThreadDiscoverySourceCapabilities(
        _mapCapabilitySet(_threadRepository.capabilities.values),
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
        diagnosticMessage: 'Comic discovery source identity is empty.',
      );
    }
    final result = await _threadRepository.getThreadDetail(
      tid: sourceTid,
      page: 1,
    );
    return result.when(
      success: (detail, threadCapabilities, metadata) {
        if (!_supportsRequiredThreadCapabilities(threadCapabilities)) {
          return unsupportedDataReadFailure(
            code: 'comic_discovery_capability_unsupported',
            diagnosticMessage:
                'The thread source cannot provide a reliable comic discovery document.',
          );
        }
        if (detail.tid.trim() != sourceTid ||
            detail.fid.trim().isEmpty ||
            !_hasValidPosts(detail.posts)) {
          return const DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_discovery_identity_invalid',
            diagnosticMessage:
                'Comic discovery thread or post identity is invalid.',
          );
        }
        try {
          return DataReadSuccess(
            data: _mapper.map(detail),
            capabilities: ComicThreadDiscoveryCapabilities(
              _mapCapabilitySet(threadCapabilities.values),
            ),
            metadata: metadata,
          );
        } catch (error) {
          return DataReadFailure(
            kind: DataReadFailureKind.parse,
            code: 'comic_discovery_projection_failed',
            diagnosticMessage: 'Comic discovery projection failed: $error',
          );
        }
      },
      failure: (failure) => failure.retype(),
    );
  }

  bool _supportsRequiredThreadCapabilities(
    ThreadDetailReadCapabilities capabilities,
  ) {
    return const <ThreadDetailCapability>[
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.forumIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.firstPostIdentity,
      ThreadDetailCapability.renderableBody,
    ].every(capabilities.supports);
  }

  bool _hasValidPosts(List<ThreadPost> posts) {
    if (posts.isEmpty) {
      return false;
    }
    final pids = <String>{};
    for (final post in posts) {
      final pid = post.pid.trim();
      if (pid.isEmpty || !pids.add(pid)) {
        return false;
      }
    }
    return true;
  }

  DataCapabilitySet<ComicThreadDiscoveryCapability> _mapCapabilitySet(
    DataCapabilitySet<ThreadDetailCapability> source,
  ) {
    return DataCapabilitySet<ComicThreadDiscoveryCapability>(
      <ComicThreadDiscoveryCapability, DataCapabilitySupport>{
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
        ComicThreadDiscoveryCapability.reliableFirstPostIdentity: source
            .supportOf(ThreadDetailCapability.firstPostIdentity),
        ComicThreadDiscoveryCapability.renderableBody: source.supportOf(
          ThreadDetailCapability.renderableBody,
        ),
        ComicThreadDiscoveryCapability.normalizedImageReferences: source
            .supportOf(ThreadDetailCapability.renderableBody),
        ComicThreadDiscoveryCapability.attachmentIdentity: source.supportOf(
          ThreadDetailCapability.attachmentMetadata,
        ),
      },
    );
  }
}
