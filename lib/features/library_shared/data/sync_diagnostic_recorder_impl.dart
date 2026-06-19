import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:y300/features/library_shared/data/sync_diagnostic_settings_repository.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

class DefaultSyncDiagnosticRecorder implements SyncDiagnosticRecorder {
  DefaultSyncDiagnosticRecorder({
    required DownloadStorageService storageService,
    required SyncDiagnosticSettingsRepository settingsRepository,
    bool debugEnabled = false,
    bool manualModeEnabled = false,
    DateTime Function()? nowProvider,
  }) : _storageService = storageService,
       _settingsRepository = settingsRepository,
       _debugEnabled = debugEnabled,
       _manualModeEnabled = manualModeEnabled,
       _active = manualModeEnabled,
       _nowProvider = nowProvider ?? DateTime.now;

  final DownloadStorageService _storageService;
  final SyncDiagnosticSettingsRepository _settingsRepository;
  final bool _debugEnabled;
  final DateTime Function() _nowProvider;

  bool _manualModeEnabled;
  bool _active;
  String? _currentLogPath;
  Future<void> _tail = Future<void>.value();

  @override
  String? get currentLogPath => _currentLogPath;

  @override
  bool get isManualModeEnabled => _manualModeEnabled;

  @override
  void activateFavoriteFirstSync() {
    if (!_debugEnabled && !_manualModeEnabled) {
      return;
    }
    _active = true;
    _scheduleWrite(() async {
      await _ensureLogPath();
      await _appendLine(
        scope: 'favorites',
        event: 'bootstrap_initial_started',
        fields: <String, Object?>{
          'logPath': _currentLogPath,
          'manualModeEnabled': _manualModeEnabled,
        },
      );
    });
  }

  @override
  Future<bool> setManualModeEnabled(bool enabled) async {
    if (_manualModeEnabled == enabled) {
      return _manualModeEnabled;
    }
    _manualModeEnabled = enabled;
    await _settingsRepository.setManualModeEnabled(enabled);
    if (enabled) {
      _active = true;
      _scheduleWrite(() async {
        await _ensureLogPath();
        await _appendLine(
          scope: 'diagnostic_mode',
          event: 'manual_mode_enabled',
          fields: <String, Object?>{
            'logPath': _currentLogPath,
          },
        );
      });
      return true;
    }
    if (_currentLogPath != null) {
      _scheduleWrite(() async {
        await _appendLine(
          scope: 'diagnostic_mode',
          event: 'manual_mode_disabled',
          fields: const <String, Object?>{},
        );
      });
    }
    _active = false;
    return false;
  }

  @override
  void record({
    required String scope,
    required String event,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (!_shouldRecord) {
      return;
    }
    _scheduleWrite(() async {
      await _ensureLogPath();
      await _appendLine(scope: scope, event: event, fields: fields);
    });
  }

  @override
  void recordHttpRequest({
    required String method,
    required Uri uri,
    required DateTime startedAt,
    required int elapsedMs,
    int? statusCode,
    bool succeeded = true,
    String? error,
    String? kind,
    String? operation,
    String? module,
    String? pageKind,
    String? requestId,
  }) {
    if (!_shouldRecord) {
      return;
    }
    record(
      scope: 'http',
      event: succeeded ? 'request_succeeded' : 'request_failed',
      fields: <String, Object?>{
        'method': method,
        'host': uri.host,
        'path': uri.path,
        'query': _stringifyQuery(uri),
        'startedAt': startedAt.toUtc().toIso8601String(),
        'elapsedMs': elapsedMs,
        'statusCode': statusCode,
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (operation != null && operation.isNotEmpty) 'operation': operation,
        if (module != null && module.isNotEmpty) 'module': module,
        if (pageKind != null && pageKind.isNotEmpty) 'pageKind': pageKind,
        if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
        if (error != null && error.isNotEmpty) 'error': error,
      },
    );
  }

  bool get _shouldRecord => (_debugEnabled || _manualModeEnabled) && _active;

  void _scheduleWrite(Future<void> Function() action) {
    _tail = _tail.then((_) => action()).catchError((_) {});
  }

  Future<void> _appendLine({
    required String scope,
    required String event,
    required Map<String, Object?> fields,
  }) async {
    final logPath = _currentLogPath;
    if (logPath == null) {
      return;
    }
    final file = io.File(logPath);
    await file.parent.create(recursive: true);
    final payload = <String, Object?>{
      'ts': _nowProvider().toUtc().toIso8601String(),
      'scope': scope,
      'event': event,
      if (fields.isNotEmpty) 'fields': fields,
    };
    await file.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: io.FileMode.append,
      encoding: utf8,
      flush: true,
    );
  }

  Future<void> _ensureLogPath() async {
    if (_currentLogPath != null) {
      return;
    }
    final root = await _storageService.prepareRoot();
    final diagnosticsDir = io.Directory(p.join(root.path, 'diagnostics'));
    await diagnosticsDir.create(recursive: true);
    final timestamp = _formatFileTimestamp(_nowProvider().toUtc());
    _currentLogPath = p.join(
      diagnosticsDir.path,
      'favorite-first-sync-$timestamp.log',
    );
  }

  String _formatFileTimestamp(DateTime value) {
    final iso = value.toIso8601String();
    return iso.replaceAll(':', '').replaceAll('.', '-');
  }

  Map<String, Object?> _stringifyQuery(Uri uri) {
    return uri.queryParameters.map(
      (key, value) => MapEntry<String, Object?>(key, value),
    );
  }
}
