import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';

class ThreadRepositoryNovelSourceMetadataRecoveryGateway
    implements NovelSourceMetadataRecoveryGateway {
  const ThreadRepositoryNovelSourceMetadataRecoveryGateway(this._repository);

  final ThreadRepository _repository;

  @override
  Future<ThreadDetailData> loadFirstPage({required String tid}) async {
    final result = await _repository.getThreadDetail(
      tid: tid,
      page: 1,
      queryParameters: const <String, String>{'version': '4'},
    );
    final data = result.dataOrNull;
    if (!result.isSuccess || data == null) {
      final message = result.errorOrNull?.message ?? '恢复小说来源信息失败';
      throw StateError(message);
    }
    return data;
  }
}

final novelSourceMetadataRecoveryGatewayProvider =
    Provider<NovelSourceMetadataRecoveryGateway>((ref) {
      return ThreadRepositoryNovelSourceMetadataRecoveryGateway(
        ref.watch(threadJsonRepositoryProvider),
      );
    });
