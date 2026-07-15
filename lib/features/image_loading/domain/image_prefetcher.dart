import 'dart:async';

/// 预取请求：描述“要提前缓存哪张图、多急、附带哪些业务数据”。
///
/// [dedupeKey] 决定去重与优先级合并的身份；[priority] 越小越急。
/// [payload] 是给 runner 的不透明业务数据（如书架封面的 workId/自定义封面信息），
/// 预取器本身不解释它——保持 business-agnostic。
class ImagePrefetchRequest {
  const ImagePrefetchRequest({
    required this.dedupeKey,
    required this.priority,
    this.payload,
  });

  final String dedupeKey;
  final int priority;
  final Object? payload;

  ImagePrefetchRequest copyWith({int? priority}) {
    return ImagePrefetchRequest(
      dedupeKey: dedupeKey,
      priority: priority ?? this.priority,
      payload: payload,
    );
  }
}

/// 执行单个预取任务的业务回调（下载、可选写回）。返回是否成功仅用于统计。
typedef ImagePrefetchRunner = Future<bool> Function(ImagePrefetchRequest request);

/// 预取器进度快照，供调用方驱动“正在预热”一类的提示。
class ImagePrefetcherSnapshot {
  const ImagePrefetcherSnapshot({
    required this.pendingCount,
    required this.runningCount,
  });

  final int pendingCount;
  final int runningCount;

  bool get isIdle => pendingCount == 0 && runningCount == 0;
}

typedef ImagePrefetcherSnapshotHandler = void Function(
  ImagePrefetcherSnapshot snapshot,
);

/// 统一图片预取器——只负责“提前量”优化的调度。
///
/// 设计要点（对齐 [图片与列表加载性能优化方案] Phase 2）：
/// - **持久存在**：不随可见区变化而销毁重建。
/// - **只重排、不清空**：[submit] 合并新窗口的优先级，不取消正在运行的任务，
///   因此快速滚动时“可见项不会被取消”，这是修复书架 cancel-restart 的关键。
/// - **business-agnostic**：具体如何下载/写回由注入的 [ImagePrefetchRunner] 决定，
///   预取器只管优先级、去重、并发。
///
/// 调度结构包含优先级排序、去重、并发上限和微任务泵，并保持通用，可被书架、
/// 帖子等多处复用。
abstract class ImagePrefetcher {
  /// 提交一个新的“可见窗口”请求集合。
  ///
  /// 已在运行的任务不受影响；待执行队列中的同 key 任务会合并取更急的优先级；
  /// 新 key 入队。不传的旧 key 保留在队列里按其原优先级继续（通常调用方在
  /// 窗口里已为全部项标了 background，自然被挤到最后）。
  void submit(List<ImagePrefetchRequest> window);

  /// 清空待执行队列（运行中的任务无法强停，仅标记不再回调）。
  void clear();

  void dispose();
}

class DefaultImagePrefetcher implements ImagePrefetcher {
  DefaultImagePrefetcher({
    required ImagePrefetchRunner runner,
    ImagePrefetcherSnapshotHandler? onSnapshot,
    int maxConcurrent = 3,
  })  : _runner = runner,
        _onSnapshot = onSnapshot,
        _maxConcurrent = maxConcurrent.clamp(1, 6).toInt();

  final ImagePrefetchRunner _runner;
  final ImagePrefetcherSnapshotHandler? _onSnapshot;
  final int _maxConcurrent;

  final Map<String, ImagePrefetchRequest> _pendingByKey =
      <String, ImagePrefetchRequest>{};
  final Set<String> _runningKeys = <String>{};
  final Set<String> _completedKeys = <String>{};
  bool _disposed = false;
  bool _pumpScheduled = false;

  @override
  void submit(List<ImagePrefetchRequest> window) {
    if (_disposed) {
      return;
    }
    for (final request in window) {
      final key = request.dedupeKey;
      // 已成功缓存或正在运行的，无需重复入队。
      if (_completedKeys.contains(key) || _runningKeys.contains(key)) {
        continue;
      }
      final existing = _pendingByKey[key];
      if (existing == null || request.priority < existing.priority) {
        _pendingByKey[key] = request;
      }
    }
    _emitSnapshot();
    _schedulePump();
  }

  @override
  void clear() {
    if (_disposed) {
      return;
    }
    _pendingByKey.clear();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pendingByKey.clear();
    _runningKeys.clear();
  }

  void _schedulePump() {
    if (_pumpScheduled || _disposed) {
      return;
    }
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_runningKeys.length < _maxConcurrent && _pendingByKey.isNotEmpty) {
      final request = _takeNext();
      if (request == null) {
        return;
      }
      _runningKeys.add(request.dedupeKey);
      _emitSnapshot();
      unawaited(_run(request));
    }
  }

  ImagePrefetchRequest? _takeNext() {
    if (_pendingByKey.isEmpty) {
      return null;
    }
    final sorted = _pendingByKey.values.toList(growable: false)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final next = sorted.first;
    _pendingByKey.remove(next.dedupeKey);
    return next;
  }

  Future<void> _run(ImagePrefetchRequest request) async {
    var success = false;
    try {
      success = await _runner(request);
    } catch (_) {
      // 预取是尽力而为：失败绝不能影响 AppImage 的自食其力展示。
      success = false;
    }
    if (_disposed) {
      return;
    }
    _runningKeys.remove(request.dedupeKey);
    if (success) {
      _completedKeys.add(request.dedupeKey);
    }
    _emitSnapshot();
    _pump();
  }

  void _emitSnapshot() {
    final handler = _onSnapshot;
    if (handler == null) {
      return;
    }
    handler(
      ImagePrefetcherSnapshot(
        pendingCount: _pendingByKey.length,
        runningCount: _runningKeys.length,
      ),
    );
  }
}
