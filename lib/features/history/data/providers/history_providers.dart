import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_database_manager.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/history/data/repositories/sqflite_history_repository.dart';
import 'package:y300/features/history/data/services/history_data_lifecycle_service.dart';
import 'package:y300/features/history/data/services/debug_history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_clock.dart';
import 'package:y300/features/history/domain/services/history_diagnostic_recorder.dart';
import 'package:y300/features/history/domain/services/history_retention_policy.dart';
import 'package:y300/features/history/domain/services/history_use_cases.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/history/domain/services/record_history_visit_use_case.dart';

final historyDatabaseNameProvider = Provider<String>((ref) {
  return HistoryLocalDb.dbName;
});

final historyDatabaseManagerProvider = Provider<HistoryDatabaseManager>((ref) {
  final manager = HistoryDatabaseManager(
    databaseName: ref.watch(historyDatabaseNameProvider),
  );
  ref.onDispose(() {
    unawaited(manager.dispose());
  });
  return manager;
});

final historyDatabaseProvider = Provider<Future<Database>>((ref) {
  return ref.watch(historyDatabaseManagerProvider).open();
});

final historyClockProvider = Provider<HistoryClock>((ref) {
  return const SystemHistoryClock();
});

final historyDiagnosticRecorderProvider = Provider<HistoryDiagnosticRecorder>((
  ref,
) {
  if (!kDebugMode) {
    return const NoopHistoryDiagnosticRecorder();
  }
  return DebugHistoryDiagnosticRecorder();
});

final historyRetentionPolicyProvider = Provider<HistoryRetentionPolicy>((ref) {
  return const HistoryRetentionPolicy();
});

final historyVisitDraftNormalizerProvider =
    Provider<HistoryVisitDraftNormalizer>((ref) {
      return const HistoryVisitDraftNormalizer();
    });

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final manager = ref.watch(historyDatabaseManagerProvider);
  final repository = SqfliteHistoryRepository.withDatabaseProvider(
    manager.open,
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
    diagnosticRecorder: ref.watch(historyDiagnosticRecorderProvider),
  );
});

final historyVisitRecorderProvider = Provider<HistoryVisitRecorder>((ref) {
  return ref.watch(recordHistoryVisitUseCaseProvider);
});

final queryHistoryUseCaseProvider = Provider<QueryHistoryUseCase>((ref) {
  return QueryHistoryUseCase(
    repository: ref.watch(historyRepositoryProvider),
    normalizer: ref.watch(historyVisitDraftNormalizerProvider),
    diagnosticRecorder: ref.watch(historyDiagnosticRecorderProvider),
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

final historyDataLifecycleServiceProvider =
    Provider<HistoryDataLifecycleService>((ref) {
      return HistoryDataLifecycleService(
        databaseManager: ref.watch(historyDatabaseManagerProvider),
        repository: ref.watch(historyRepositoryProvider),
      );
    });
