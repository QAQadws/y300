import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/data/repositories/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';

void main() {
  group('DefaultThreadFavoriteActionService', () {
    test(
      'favorites thread then refreshes favorite module and notifies listener',
      () async {
        final repository = _FakeThreadFavoriteRepository();
        var refreshCalled = false;
        final reasons = <String>[];
        final tids = <String>[];
        final service = DefaultThreadFavoriteActionService(
          repository: repository,
          refreshFavoriteModule: ({required String tid}) async {
            refreshCalled = true;
            expect(tid, '570617');
          },
          notifyFavoriteModule:
              ({required String reason, required String tid}) {
                reasons.add(reason);
                tids.add(tid);
              },
        );

        final result = await service.favoriteThread(tid: '570617');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.refreshedFavoriteModule, isTrue);
        expect(repository.lastTid, '570617');
        expect(refreshCalled, isTrue);
        expect(reasons, <String>['thread_favorite_added']);
        expect(tids, <String>['570617']);
      },
    );

    test(
      'keeps remote favorite success when favorite module refresh fails',
      () async {
        final repository = _FakeThreadFavoriteRepository();
        final reasons = <String>[];
        final tids = <String>[];
        final service = DefaultThreadFavoriteActionService(
          repository: repository,
          refreshFavoriteModule: ({required String tid}) async {
            throw StateError('sync failed');
          },
          notifyFavoriteModule:
              ({required String reason, required String tid}) {
                reasons.add(reason);
                tids.add(tid);
              },
        );

        final result = await service.favoriteThread(tid: '570617');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull?.refreshedFavoriteModule, isFalse);
        expect(result.dataOrNull?.message, contains('收藏列表刷新失败'));
        expect(reasons, <String>['thread_favorite_added_sync_failed']);
        expect(tids, <String>['570617']);
      },
    );

    test(
      'does not refresh favorite module when remote favorite fails',
      () async {
        final repository = _FakeThreadFavoriteRepository(
          result: const ApiFailure<ThreadFavoriteResult>(
            ApiError(type: ApiErrorType.business, message: '未登录'),
          ),
        );
        var refreshCalled = false;
        final reasons = <String>[];
        final service = DefaultThreadFavoriteActionService(
          repository: repository,
          refreshFavoriteModule: ({required String tid}) async {
            refreshCalled = true;
          },
          notifyFavoriteModule:
              ({required String reason, required String tid}) {
                reasons.add(reason);
              },
        );

        final result = await service.favoriteThread(tid: '570617');

        expect(result.isFailure, isTrue);
        expect(refreshCalled, isFalse);
        expect(reasons, isEmpty);
      },
    );
  });
}

class _FakeThreadFavoriteRepository implements ThreadFavoriteRepository {
  _FakeThreadFavoriteRepository({
    this.result = const ApiSuccess<ThreadFavoriteResult>(
      ThreadFavoriteResult(message: '收藏成功'),
    ),
  });

  final ApiResult<ThreadFavoriteResult> result;
  String? lastTid;

  @override
  Future<ApiResult<ThreadFavoriteResult>> favoriteThread({
    required ThreadFavoriteRequest request,
  }) async {
    lastTid = request.tid;
    return result;
  }

  @override
  Future<ApiResult<ThreadUnfavoriteResult>> unfavoriteThread({
    required ThreadUnfavoriteRequest request,
  }) async {
    lastTid = request.tid;
    return const ApiSuccess<ThreadUnfavoriteResult>(
      ThreadUnfavoriteResult(message: '取消收藏成功'),
    );
  }
}
