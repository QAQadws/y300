import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_recorder_impl.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_settings_repository.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final syncDiagnosticInitialManualModeProvider = Provider<bool>((ref) => false);

final syncDiagnosticSettingsRepositoryProvider =
    Provider<SyncDiagnosticSettingsRepository>((ref) {
      return SharedPrefsSyncDiagnosticSettingsRepository();
    });

final syncDiagnosticRecorderProvider = Provider<SyncDiagnosticRecorder>((ref) {
  final settings = ref.watch(syncDiagnosticSettingsRepositoryProvider);
  final initialManualMode = ref.watch(syncDiagnosticInitialManualModeProvider);
  return DefaultSyncDiagnosticRecorder(
    storageService: ref.watch(downloadStorageServiceProvider),
    settingsRepository: settings,
    debugEnabled: kDebugMode,
    manualModeEnabled: initialManualMode,
  );
});
