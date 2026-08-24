import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';

class ThreadRepositoryNovelSourceMetadataRecoveryGateway
    implements NovelSourceMetadataRecoveryGateway {
  const ThreadRepositoryNovelSourceMetadataRecoveryGateway(this._repository);

  final ThreadRepository _repository;

  @override
  Future<ThreadDetailData> loadFirstPage({required String tid}) async {
    final result = await _repository.getThreadDetail(tid: tid, page: 1);
    final data = result.dataOrNull;
    if (!result.isSuccess || data == null) {
      final message = result.failureOrNull?.diagnosticMessage ?? '恢复小说来源信息失败';
      throw StateError(message);
    }
    return data;
  }
}

final novelSourceMetadataRecoveryGatewayProvider =
    Provider<NovelSourceMetadataRecoveryGateway>((ref) {
      return ThreadRepositoryNovelSourceMetadataRecoveryGateway(
        ref.watch(threadIngestionRepositoryProvider),
      );
    });
