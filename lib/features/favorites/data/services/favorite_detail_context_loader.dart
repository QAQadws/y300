import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_detail_context.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef FavoriteThreadDetailLoader =
    Future<ApiResult<ThreadDetailData>> Function(String tid);
typedef FavoriteTagLookupLoader = Future<ForumTagLookup> Function();

abstract class FavoriteDetailContextLoader {
  Future<ApiResult<ThreadDetailData>> loadDetail(
    String tid, {
    FavoriteSyncExecutionContext? executionContext,
  });

  Future<ApiResult<FavoriteDetailResolution>> load(
    FavoriteThreadCacheRecord record, {
    ThreadDetailData? preloadedDetail,
    FavoriteSyncExecutionContext? executionContext,
  });
}

class DefaultFavoriteDetailContextLoader
    implements FavoriteDetailContextLoader {
  const DefaultFavoriteDetailContextLoader({
    required FavoriteThreadDetailLoader loadThreadDetail,
    required FavoriteTagLookupLoader loadTagLookup,
    required ThreadContentClassifier classifier,
    SyncDiagnosticRecorder? diagnosticRecorder,
  }) : _loadThreadDetail = loadThreadDetail,
       _loadTagLookup = loadTagLookup,
       _classifier = classifier,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopSyncDiagnosticRecorder();

  final FavoriteThreadDetailLoader _loadThreadDetail;
  final FavoriteTagLookupLoader _loadTagLookup;
  final ThreadContentClassifier _classifier;
  final SyncDiagnosticRecorder _diagnosticRecorder;

  @override
  Future<ApiResult<ThreadDetailData>> loadDetail(
    String tid, {
    FavoriteSyncExecutionContext? executionContext,
  }) {
    _diagnosticRecorder.record(
      scope: 'favorite_detail',
      event: 'load_thread_detail',
      fields: <String, Object?>{
        'tid': tid,
        'governed': executionContext?.governor != null,
      },
    );
    final governor = executionContext?.governor;
    if (governor == null) {
      return _loadThreadDetail(tid);
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.favoriteThreadDetail,
      action: () => _loadThreadDetail(tid),
    );
  }

  @override
  Future<ApiResult<FavoriteDetailResolution>> load(
    FavoriteThreadCacheRecord record, {
    ThreadDetailData? preloadedDetail,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final ApiResult<ThreadDetailData> detailResult;
    if (preloadedDetail != null) {
      detailResult = ApiSuccess<ThreadDetailData>(preloadedDetail);
    } else {
      detailResult = await loadDetail(
        record.tid,
        executionContext: executionContext,
      );
    }
    if (detailResult is ApiFailure<ThreadDetailData>) {
      return ApiFailure<FavoriteDetailResolution>(detailResult.error);
    }
    final detail = detailResult.dataOrNull;
    if (detail == null) {
      return const ApiFailure<FavoriteDetailResolution>(
        ApiError(type: ApiErrorType.network, message: '加载帖子详情失败'),
      );
    }

    if (detail.posts.isEmpty) {
      return ApiSuccess<FavoriteDetailResolution>(
        InvalidFavoriteDetail(record: record, detail: detail),
      );
    }

    final tagName = await _findTagName(fid: detail.fid, typeid: detail.typeid);
    final kind = _classifier.classify(
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
    );
    return ApiSuccess<FavoriteDetailResolution>(
      ResolvedFavoriteDetail(
        FavoriteDetailContext(
          record: record,
          detail: detail,
          kind: kind,
          tagName: tagName,
        ),
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
