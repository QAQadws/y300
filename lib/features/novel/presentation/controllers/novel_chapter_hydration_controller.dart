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
    this.failureCode,
    this.diagnosticDetail,
  });

  final NovelChapterHydrationViewStatus status;
  final NovelChapterSyncProgress? progress;
  final NovelChapterSyncFailureCode? failureCode;
  final Object? diagnosticDetail;

  bool get isReady => status == NovelChapterHydrationViewStatus.ready;
  bool get canRetry => status == NovelChapterHydrationViewStatus.failed;

  NovelChapterHydrationViewState copyWith({
    NovelChapterHydrationViewStatus? status,
    NovelChapterSyncProgress? progress,
    NovelChapterSyncFailureCode? failureCode,
    Object? diagnosticDetail,
    bool clearFailure = false,
  }) {
    return NovelChapterHydrationViewState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      failureCode: clearFailure ? null : (failureCode ?? this.failureCode),
      diagnosticDetail: clearFailure
          ? null
          : (diagnosticDetail ?? this.diagnosticDetail),
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
        failureCode: NovelChapterSyncFailureCode.missingSourceState,
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
        failureCode: NovelChapterSyncFailureCodeCodec.fromStorage(
          sourceState.lastError,
        ),
      );
    }
    if (sourceState.hydrationState == NovelChapterHydrationState.hydrating &&
        !ref.read(novelChapterSyncServiceProvider).hasActiveRun(_novelId)) {
      const failureCode = NovelChapterSyncFailureCode.interrupted;
      await ref
          .read(novelSourceStateRepositoryProvider)
          .setHydrationState(
            novelId: _novelId,
            state: NovelChapterHydrationState.failed,
            lastError: failureCode.storageValue,
          );
      return const NovelChapterHydrationViewState(
        status: NovelChapterHydrationViewStatus.failed,
        failureCode: failureCode,
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
        throw const NovelChapterSyncException(
          NovelChapterSyncFailureCode.missingSourceState,
        );
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
        throw const NovelChapterSyncException(
          NovelChapterSyncFailureCode.missingPublisherId,
        );
      }

      final detail = await ref
          .read(novelRepositoryProvider)
          .getDetail(novelId: _novelId);
      final tid = detail?.sourceTid.trim() ?? '';
      if (tid.isEmpty) {
        throw const NovelChapterSyncException(
          NovelChapterSyncFailureCode.missingSourceTid,
        );
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
            failureCode: progress.failureCode,
            diagnosticDetail: progress.diagnosticDetail,
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
      final failureCode = _failureCode(error);
      try {
        await ref
            .read(novelSourceStateRepositoryProvider)
            .setHydrationState(
              novelId: _novelId,
              state: NovelChapterHydrationState.failed,
              lastError: failureCode.storageValue,
            );
      } catch (_) {
        // The visible error remains useful even when the source row is missing.
      }
      if (ref.mounted) {
        state = AsyncData(
          NovelChapterHydrationViewState(
            status: NovelChapterHydrationViewStatus.failed,
            failureCode: failureCode,
            diagnosticDetail: error is NovelChapterSyncException
                ? error.detail
                : error,
          ),
        );
      }
    }
  }

  NovelChapterSyncFailureCode _failureCode(Object error) {
    return error is NovelChapterSyncException
        ? error.code
        : NovelChapterSyncFailureCode.synchronizationFailed;
  }

  void _removeOperation(Future<void> operation) {
    if (identical(_operation, operation)) {
      _operation = null;
    }
  }
}
