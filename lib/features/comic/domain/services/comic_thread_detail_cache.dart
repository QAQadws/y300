import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

/// 单次刷新内复用的 thread detail 缓存。
///
/// - 在 `ComicEpisodeDiscoveryService._fetchAndParse` 命中时跳过 HTTP；
/// - 在 `ComicFirstEpisodeCoverService.promoteIfPossible` 时优先复用缓存
///   里第一话的解析结果，避免封面拉取再发一次 viewthread。
///
/// 故意不做 LRU/容量限制：单次刷新触达的 tid 集很小（≤几十），
/// 生命周期由调用方持有（一次刷新结束即被丢弃）。
class ComicThreadDetailCache {
  ComicThreadDetailCache();

  final Map<String, ThreadDetailData> _byTid = <String, ThreadDetailData>{};

  ThreadDetailData? get(String tid) => _byTid[tid];

  void store(ThreadDetailData detail) {
    final tid = detail.tid.trim();
    if (tid.isEmpty) {
      return;
    }
    _byTid[tid] = detail;
  }

  bool contains(String tid) => _byTid.containsKey(tid);

  int get size => _byTid.length;
}
