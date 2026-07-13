import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

enum NovelChapterHydrationViewStatus {
  pending,
  recoveringMetadata,
  hydrating,
  ready,
  failed,
}

class NovelChapterHydrationViewState {
  const NovelChapterHydrationViewState({
    required this.status,
    this.progress,
    this.errorMessage,
  });

  final NovelChapterHydrationViewStatus status;
  final NovelChapterSyncProgress? progress;
  final String? errorMessage;

  bool get isReady => status == NovelChapterHydrationViewStatus.ready;
  bool get canRetry => status == NovelChapterHydrationViewStatus.failed;

  NovelChapterHydrationViewState copyWith({
    NovelChapterHydrationViewStatus? status,
    NovelChapterSyncProgress? progress,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NovelChapterHydrationViewState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final novelChapterHydrationControllerProvider = AsyncNotifierProvider
    .autoDispose
    .family<
      NovelChapterHydrationController,
      NovelChapterHydrationViewState,
      String
    >((novelId) => NovelChapterHydrationController(novelId));

class NovelChapterHydrationController
    extends AsyncNotifier<NovelChapterHydrationViewState> {
  NovelChapterHydrationController(this._novelId);

  final String _novelId;
  StreamSubscription<NovelChapterSyncProgress>? _progressSubscription;
  Future<void>? _operation;

  @override
  FutureOr<NovelChapterHydrationViewState> build() async {
    ref.onDispose(() => _progressSubscription?.cancel());
    final sourceState = await ref
        .read(novelSourceStateRepositoryProvider)
        .getSourceState(novelId: _novelId);
    if (sourceState == null) {
      return const NovelChapterHydrationViewState(
        status: NovelChapterHydrationViewStatus.failed,
        errorMessage: '缺少小说来源信息，无法加载章节。',
      );
    }
    if (sourceState.hydrationState == NovelChapterHydrationState.ready) {
      return const NovelChapterHydrationViewState(
        status: NovelChapterHydrationViewStatus.ready,
      );
    }
    if (sourceState.hydrationState == NovelChapterHydrationState.failed) {
      return NovelChapterHydrationViewState(
        status: NovelChapterHydrationViewStatus.failed,
        errorMessage: sourceState.lastError ?? '章节加载失败，请重试。',
      );
    }
    if (sourceState.hydrationState == NovelChapterHydrationState.hydrating &&
        !ref.read(novelChapterSyncServiceProvider).hasActiveRun(_novelId)) {
      const message = '上次章节加载被中断，请重试。';
      await ref
          .read(novelSourceStateRepositoryProvider)
          .setHydrationState(
            novelId: _novelId,
            state: NovelChapterHydrationState.failed,
            lastError: message,
          );
      return const NovelChapterHydrationViewState(
        status: NovelChapterHydrationViewStatus.failed,
        errorMessage: message,
      );
    }
    return const NovelChapterHydrationViewState(
      status: NovelChapterHydrationViewStatus.pending,
    );
  }

  Future<void> ensureHydrated() async {
    final current = state.value;
    if (current == null ||
        current.status != NovelChapterHydrationViewStatus.pending) {
      return;
    }
    await _startHydration();
  }

  Future<void> retry() async {
    if (state.value?.canRetry != true) {
      return;
    }
    await _startHydration();
  }

  Future<void> _startHydration() {
    final existing = _operation;
    if (existing != null) {
      return existing;
    }
    final operation = _runHydration();
    _operation = operation;
    unawaited(
      operation.then<void>(
        (_) => _removeOperation(operation),
        onError: (_, _) => _removeOperation(operation),
      ),
    );
    return operation;
  }

  Future<void> _runHydration() async {
    try {
      var sourceState = await ref
          .read(novelSourceStateRepositoryProvider)
          .getSourceState(novelId: _novelId);
      if (sourceState == null) {
        throw StateError('缺少小说来源信息。');
      }
      var publisherId = sourceState.publisherId?.trim() ?? '';
      if (publisherId.isEmpty) {
        state = const AsyncData(
          NovelChapterHydrationViewState(
            status: NovelChapterHydrationViewStatus.recoveringMetadata,
          ),
        );
        await ref
            .read(novelSourceMetadataRecoveryServiceProvider)
            .recover(_novelId);
        sourceState = await ref
            .read(novelSourceStateRepositoryProvider)
            .getSourceState(novelId: _novelId);
        publisherId = sourceState?.publisherId?.trim() ?? '';
      }
      if (publisherId.isEmpty) {
        throw StateError('来源帖子缺少有效的发布者 ID。');
      }

      final detail = await ref
          .read(novelRepositoryProvider)
          .getDetail(novelId: _novelId);
      final tid = detail?.sourceTid.trim() ?? '';
      if (tid.isEmpty) {
        throw StateError('小说缺少来源帖子 ID。');
      }

      final syncService = ref.read(novelChapterSyncServiceProvider);
      await _progressSubscription?.cancel();
      _progressSubscription = syncService.watchProgress(_novelId).listen((
        progress,
      ) {
        if (!ref.mounted) {
          return;
        }
        state = AsyncData(
          NovelChapterHydrationViewState(
            status: progress.phase == NovelChapterSyncPhase.completed
                ? NovelChapterHydrationViewStatus.ready
                : NovelChapterHydrationViewStatus.hydrating,
            progress: progress,
            errorMessage: progress.message,
          ),
        );
      });
      state = const AsyncData(
        NovelChapterHydrationViewState(
          status: NovelChapterHydrationViewStatus.hydrating,
        ),
      );
      await syncService.synchronize(
        NovelChapterSyncRequest(
          novelId: _novelId,
          tid: tid,
          publisherId: publisherId,
          mode: NovelChapterSyncMode.initialFull,
          checkpoint: sourceState?.checkpoint,
        ),
      );
      if (ref.mounted) {
        state = const AsyncData(
          NovelChapterHydrationViewState(
            status: NovelChapterHydrationViewStatus.ready,
          ),
        );
      }
    } catch (error) {
      final message = _errorMessage(error);
      try {
        await ref
            .read(novelSourceStateRepositoryProvider)
            .setHydrationState(
              novelId: _novelId,
              state: NovelChapterHydrationState.failed,
              lastError: message,
            );
      } catch (_) {
        // The visible error remains useful even when the source row is missing.
      }
      if (ref.mounted) {
        state = AsyncData(
          NovelChapterHydrationViewState(
            status: NovelChapterHydrationViewStatus.failed,
            errorMessage: message,
          ),
        );
      }
    }
  }

  String _errorMessage(Object error) {
    return error
        .toString()
        .replaceAll(RegExp(r'^\w+(?:Exception)?:\s*'), '')
        .trim();
  }

  void _removeOperation(Future<void> operation) {
    if (identical(_operation, operation)) {
      _operation = null;
    }
  }
}
