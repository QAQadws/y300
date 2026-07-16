import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/history/data/repositories/sqflite_history_repository.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_retention_policy.dart';
import 'package:y300/features/history/domain/services/history_use_cases.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/history/domain/services/record_history_visit_use_case.dart';

final historyDatabaseNameProvider = Provider<String>((ref) {
  return HistoryLocalDb.dbName;
});

final historyDatabaseProvider = Provider<Future<Database>>((ref) {
  final database = HistoryLocalDb.open(
    databaseName: ref.watch(historyDatabaseNameProvider),
  );
  ref.onDispose(() {
    unawaited(_closeHistoryDatabase(database));
  });
  return database;
});

final historyClockProvider = Provider<HistoryClock>((ref) {
  return const SystemHistoryClock();
});

final historyRetentionPolicyProvider = Provider<HistoryRetentionPolicy>((ref) {
  return const HistoryRetentionPolicy();
});

final historyVisitDraftNormalizerProvider =
    Provider<HistoryVisitDraftNormalizer>((ref) {
      return const HistoryVisitDraftNormalizer();
    });

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final repository = SqfliteHistoryRepository(
    ref.watch(historyDatabaseProvider),
    retentionPolicy: ref.watch(historyRetentionPolicyProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final recordHistoryVisitUseCaseProvider = Provider<RecordHistoryVisitUseCase>((
  ref,
) {
  return RecordHistoryVisitUseCase(
    repository: ref.watch(historyRepositoryProvider),
    normalizer: ref.watch(historyVisitDraftNormalizerProvider),
    clock: ref.watch(historyClockProvider),
  );
});

final historyVisitRecorderProvider = Provider<HistoryVisitRecorder>((ref) {
  return ref.watch(recordHistoryVisitUseCaseProvider);
});

final queryHistoryUseCaseProvider = Provider<QueryHistoryUseCase>((ref) {
  return QueryHistoryUseCase(
    repository: ref.watch(historyRepositoryProvider),
    normalizer: ref.watch(historyVisitDraftNormalizerProvider),
  );
});

final deleteHistoryEntryUseCaseProvider = Provider<DeleteHistoryEntryUseCase>((
  ref,
) {
  return DeleteHistoryEntryUseCase(ref.watch(historyRepositoryProvider));
});

final restoreHistoryEntryUseCaseProvider = Provider<RestoreHistoryEntryUseCase>(
  (ref) {
    return RestoreHistoryEntryUseCase(ref.watch(historyRepositoryProvider));
  },
);

final clearHistoryUseCaseProvider = Provider<ClearHistoryUseCase>((ref) {
  return ClearHistoryUseCase(ref.watch(historyRepositoryProvider));
});

Future<void> _closeHistoryDatabase(Future<Database> database) async {
  try {
    final value = await database;
    if (value.isOpen) {
      await value.close();
    }
  } catch (_) {
    // Opening errors are reported to consumers; disposal must not emit a
    // second unhandled asynchronous error while the provider tree is closing.
  }
}
