import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_recorder_impl.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_settings_repository.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  test('manual mode enables recorder and writes http request event', () async {
    final rootDir = await io.Directory.systemTemp.createTemp(
      'sync-diagnostic-recorder-test',
    );
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    final recorder = DefaultSyncDiagnosticRecorder(
      storageService: _FakeDownloadStorageService(rootDir.path),
      settingsRepository: _FakeSyncDiagnosticSettingsRepository(),
      debugEnabled: false,
      manualModeEnabled: false,
      nowProvider: () => DateTime.utc(2026, 6, 14, 12, 0, 0),
    );

    await recorder.setManualModeEnabled(true);
    recorder.recordHttpRequest(
      method: 'GET',
      uri: Uri.parse(
        'https://bbs.yamibo.com/api/mobile/index.php?module=viewthread&tid=123',
      ),
      startedAt: DateTime.utc(2026, 6, 14, 11, 59, 59),
      elapsedMs: 234,
      statusCode: 200,
      succeeded: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final logPath = recorder.currentLogPath;
    expect(logPath, isNotNull);

    final file = io.File(logPath!);
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines(encoding: utf8);
    expect(lines, isNotEmpty);

    final payloads = lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);
    expect(
      payloads.any(
        (item) => item['scope'] == 'http' && item['event'] == 'request_succeeded',
      ),
      isTrue,
    );
  });
}

class _FakeSyncDiagnosticSettingsRepository
    implements SyncDiagnosticSettingsRepository {
  bool enabled = false;

  @override
  Future<bool> loadManualModeEnabled() async => enabled;

  @override
  Future<void> setManualModeEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

class _FakeDownloadStorageService implements DownloadStorageService {
  _FakeDownloadStorageService(this.rootPath);

  final String rootPath;

  @override
  Future<DownloadStorageRoot> prepareRoot() async {
    final root = io.Directory(rootPath);
    final comics = io.Directory(io.Platform.pathSeparator == '\\'
        ? '$rootPath\\comics'
        : '$rootPath/comics');
    final novels = io.Directory(io.Platform.pathSeparator == '\\'
        ? '$rootPath\\novels'
        : '$rootPath/novels');
    await root.create(recursive: true);
    await comics.create(recursive: true);
    await novels.create(recursive: true);
    final favorites = io.File(io.Platform.pathSeparator == '\\'
        ? '$rootPath\\favorites.json'
        : '$rootPath/favorites.json');
    if (!await favorites.exists()) {
      await favorites.writeAsString('{}', encoding: utf8);
    }
    return DownloadStorageRoot(
      path: root.path,
      comicsPath: comics.path,
      novelsPath: novels.path,
      favoritesJsonPath: favorites.path,
    );
  }

  @override
  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<io.Directory> prepareNovelDirectory({
    required String novelId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) {
    throw UnimplementedError();
  }

  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) {
    throw UnimplementedError();
  }

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({
    required String novelId,
    required String title,
    required String episodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> deleteComicDownloads({required String workId}) async {
    return false;
  }

  @override
  Future<bool> deleteNovelDownloads({required String novelId}) async {
    return false;
  }
}
