import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:y300/features/app_update/domain/models/app_update_artifact_identity.dart';
import 'package:y300/features/app_update/domain/services/app_update_file_store.dart';

typedef AppUpdateSupportDirectoryProvider = Future<Directory> Function();

final class LocalAppUpdateFileStore implements AppUpdateFileStore {
  LocalAppUpdateFileStore({
    AppUpdateSupportDirectoryProvider? applicationSupportDirectoryProvider,
    DateTime Function()? now,
    this.staleArtifactAge = const Duration(days: 7),
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  static const String _updatesDirectoryName = 'updates';
  static const String _stagingDirectoryName = 'staging';
  static const String _verifiedDirectoryName = 'verified';

  final AppUpdateSupportDirectoryProvider _applicationSupportDirectoryProvider;
  final DateTime Function() _now;
  final Duration staleArtifactAge;
  Future<Directory>? _supportDirectory;

  @override
  Future<String> stagingPath(AppUpdateArtifactIdentity identity) async {
    final directory = await _managedDirectory(_stagingDirectoryName);
    return p.join(directory.path, _validatedStagingFileName(identity));
  }

  @override
  Future<String> verifiedPath(AppUpdateArtifactIdentity identity) async {
    final directory = await _managedDirectory(_verifiedDirectoryName);
    return p.join(directory.path, _validatedApkFileName(identity));
  }

  @override
  Future<bool> exists(String path) async {
    final root = await _updatesRoot();
    _validateManagedPath(path, root);
    return File(path).exists();
  }

  @override
  Stream<List<int>> openRead(String path) {
    return Stream<String>.fromFuture(_updatesRoot()).asyncExpand((root) {
      _validateManagedPath(path, root);
      return File(path).openRead();
    });
  }

  @override
  Future<void> promote({
    required String stagingPath,
    required String verifiedPath,
  }) async {
    final root = await _updatesRoot();
    final stagingDirectory = p.join(root, _stagingDirectoryName);
    final verifiedDirectory = p.join(root, _verifiedDirectoryName);
    _validateManagedPath(stagingPath, root);
    _validateManagedPath(verifiedPath, root);
    if (!_isDirectChildOf(stagingPath, stagingDirectory) ||
        !p.basename(stagingPath).endsWith('.apk.part') ||
        !_isDirectChildOf(verifiedPath, verifiedDirectory) ||
        !p.basename(verifiedPath).endsWith('.apk') ||
        p.basename(stagingPath).replaceFirst('.part', '') !=
            p.basename(verifiedPath)) {
      throw const FileSystemException('Invalid update promotion paths.');
    }

    final source = File(stagingPath);
    final destination = File(verifiedPath);
    if (!await source.exists()) {
      throw const FileSystemException('The staging APK does not exist.');
    }
    await destination.parent.create(recursive: true);
    if (await destination.exists()) {
      await destination.delete();
    }
    // Both directories live below application support, so rename is a
    // same-filesystem promotion and never exposes the .part path to callers.
    await source.rename(destination.path);
  }

  @override
  Future<void> deleteArtifact(AppUpdateArtifactIdentity identity) async {
    final paths = <String>[
      await stagingPath(identity),
      await verifiedPath(identity),
    ];
    for (final path in paths) {
      final file = File(path);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // Cleanup is best effort and must not block a later retry.
      }
    }
  }

  @override
  Future<void> cleanupStaleArtifacts() async {
    final directory = await _managedDirectory(_stagingDirectoryName);
    final cutoff = _now().subtract(staleArtifactAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !p.basename(entity.path).endsWith('.apk.part')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Another process may have cleaned the orphan first.
      }
    }
  }

  Future<Directory> _managedDirectory(String child) async {
    final directory = Directory(p.join(await _updatesRoot(), child));
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _updatesRoot() async {
    final support = await (_supportDirectory ??=
        _applicationSupportDirectoryProvider());
    return p.join(support.path, _updatesDirectoryName);
  }

  String _validatedStagingFileName(AppUpdateArtifactIdentity identity) {
    final fileName = identity.stagingFileName;
    if (!_isSafeFileName(fileName) || !fileName.endsWith('.apk.part')) {
      throw ArgumentError.value(identity.fileName, 'fileName');
    }
    return fileName;
  }

  String _validatedApkFileName(AppUpdateArtifactIdentity identity) {
    final fileName = identity.fileName;
    if (!_isSafeFileName(fileName) || !fileName.endsWith('.apk')) {
      throw ArgumentError.value(fileName, 'fileName');
    }
    return fileName;
  }

  void _validateManagedPath(String path, String root) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalizedPath = p.normalize(p.absolute(path));
    final rootPrefix = '$normalizedRoot${p.separator}';
    if (!normalizedPath.startsWith(rootPrefix)) {
      throw ArgumentError.value(path, 'path', 'Path is outside updates root.');
    }
  }

  bool _isDirectChildOf(String path, String directory) {
    final relative = p.relative(path, from: directory);
    return relative.isNotEmpty && !relative.contains(p.separator);
  }

  bool _isSafeFileName(String fileName) {
    return fileName.isNotEmpty &&
        p.basename(fileName) == fileName &&
        !fileName.contains('..');
  }
}
