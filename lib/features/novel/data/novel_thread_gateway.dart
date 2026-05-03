import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';

class ThreadRepositoryNovelGateway implements NovelThreadGateway {
  const ThreadRepositoryNovelGateway(this._threadRepository);

  final ThreadRepository _threadRepository;

  @override
  Future<ThreadDetailData> getThreadDetail({required String tid, required int page}) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: page);
    final data = result.dataOrNull;
    if (!result.isSuccess || data == null) {
      final message = result.errorOrNull?.message ?? '加载帖子详情失败';
      throw StateError(message);
    }
    return data;
  }
}

final novelThreadGatewayProvider = Provider<NovelThreadGateway>((ref) {
  return ThreadRepositoryNovelGateway(ref.watch(threadRepositoryProvider));
});
