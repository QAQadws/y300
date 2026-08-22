import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_detail_context.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef FavoriteTagLookupLoader = Future<ForumTagLookup> Function();

abstract class FavoriteDetailContextLoader {
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  loadDetail(String tid, {FavoriteSyncExecutionContext? executionContext});

  Future<
    DataReadResult<FavoriteDetailResolution, FavoriteDetailReadCapabilities>
  >
  load(
    FavoriteThreadCacheRecord record, {
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?
    preloadedDetail,
    FavoriteSyncExecutionContext? executionContext,
  });
}

class DefaultFavoriteDetailContextLoader
    implements FavoriteDetailContextLoader {
  const DefaultFavoriteDetailContextLoader({
    required ThreadRepository threadRepository,
    required FavoriteTagLookupLoader loadTagLookup,
    required ThreadContentClassifier classifier,
  }) : _threadRepository = threadRepository,
       _loadTagLookup = loadTagLookup,
       _classifier = classifier;

  final ThreadRepository _threadRepository;
  final FavoriteTagLookupLoader _loadTagLookup;
  final ThreadContentClassifier _classifier;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  loadDetail(String tid, {FavoriteSyncExecutionContext? executionContext}) {
    final governor = executionContext?.governor;
    if (governor == null) {
      return _threadRepository.getThreadDetail(tid: tid, page: 1);
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.favoriteThreadDetail,
      action: () => _threadRepository.getThreadDetail(tid: tid, page: 1),
    );
  }

  @override
  Future<
    DataReadResult<FavoriteDetailResolution, FavoriteDetailReadCapabilities>
  >
  load(
    FavoriteThreadCacheRecord record, {
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?
    preloadedDetail,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>
    detailResult;
    if (preloadedDetail != null) {
      detailResult = preloadedDetail;
    } else {
      detailResult = await loadDetail(
        record.tid,
        executionContext: executionContext,
      );
    }
    if (detailResult
        case final DataReadFailure<
              ThreadDetailData,
              ThreadDetailReadCapabilities
            >
            failure) {
      return failure.retype();
    }
    final success =
        detailResult
            as DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>;
    final capabilityFailure = _validateCapabilities(success.capabilities);
    if (capabilityFailure != null) {
      return capabilityFailure;
    }
    final detail = success.data;
    final capabilities = _mapCapabilities(success.capabilities);

    if (detail.posts.isEmpty) {
      return DataReadSuccess(
        data: InvalidFavoriteDetail(record: record, detail: detail),
        capabilities: capabilities,
        metadata: success.metadata,
      );
    }

    final tagName = await _findTagName(fid: detail.fid, typeid: detail.typeid);
    final kind = _classifier.classify(
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
    );
    return DataReadSuccess(
      data: ResolvedFavoriteDetail(
        FavoriteDetailContext(
          record: record,
          detail: detail,
          kind: kind,
          tagName: tagName,
        ),
      ),
      capabilities: capabilities,
      metadata: success.metadata,
    );
  }

  DataReadFailure<FavoriteDetailResolution, FavoriteDetailReadCapabilities>?
  _validateCapabilities(ThreadDetailReadCapabilities capabilities) {
    const requiredCapabilities = <ThreadDetailCapability>[
      ThreadDetailCapability.threadIdentity,
      ThreadDetailCapability.forumIdentity,
      ThreadDetailCapability.orderedPosts,
      ThreadDetailCapability.renderableBody,
    ];
    if (requiredCapabilities.every(capabilities.supports)) {
      return null;
    }
    return unsupportedDataReadFailure(
      code: 'favorite_detail_capability_unsupported',
      diagnosticMessage:
          'The detail source cannot provide favorite classification data.',
    );
  }

  FavoriteDetailReadCapabilities _mapCapabilities(
    ThreadDetailReadCapabilities source,
  ) {
    return FavoriteDetailReadCapabilities(
      DataCapabilitySet<FavoriteDetailCapability>(
        <FavoriteDetailCapability, DataCapabilitySupport>{
          FavoriteDetailCapability.stableThreadIdentity: source.values
              .supportOf(ThreadDetailCapability.threadIdentity),
          FavoriteDetailCapability.forumClassification: source.values.supportOf(
            ThreadDetailCapability.forumIdentity,
          ),
          FavoriteDetailCapability.orderedPosts: source.values.supportOf(
            ThreadDetailCapability.orderedPosts,
          ),
          FavoriteDetailCapability.renderableBody: source.values.supportOf(
            ThreadDetailCapability.renderableBody,
          ),
          FavoriteDetailCapability.attachmentMetadata: source.values.supportOf(
            ThreadDetailCapability.attachmentMetadata,
          ),
        },
      ),
    );
  }

  Future<String?> _findTagName({
    required String fid,
    required String typeid,
  }) async {
    if (fid.trim().isEmpty || typeid.trim().isEmpty) {
      return null;
    }
    try {
      final lookup = await _loadTagLookup();
      return lookup.findName(fid: fid, typeid: typeid);
    } catch (_) {
      return null;
    }
  }
}
