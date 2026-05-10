import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

abstract class StorageLocationRepository {
  Future<String> getDefaultStorageRoot();

  Future<String?> getCustomStorageRoot();

  Future<void> setCustomStorageRoot(String? path);

  Future<String?> pickDirectory();
}

class StorageLocationRepositoryImpl implements StorageLocationRepository {
  const StorageLocationRepositoryImpl({
    String androidPackageName = 'com.example.y300',
  }) : _androidPackageName = androidPackageName;

  final String _androidPackageName;

  @override
  Future<String> getDefaultStorageRoot() async {
    if (io.Platform.isAndroid) {
      final mediaRoot = io.Directory(
        p.join(
          '/storage/emulated/0/Android/media',
          _androidPackageName,
          'Y300',
        ),
      );
      if (await _canPrepare(mediaRoot)) {
        return mediaRoot.path;
      }

      final external = await getExternalStorageDirectory();
      if (external != null) {
        final fallback = io.Directory(p.join(external.path, 'Y300'));
        if (await _canPrepare(fallback)) {
          return fallback.path;
        }
      }
    }

    final documents = await getApplicationDocumentsDirectory();
    final fallback = io.Directory(p.join(documents.path, 'Y300'));
    await fallback.create(recursive: true);
    return fallback.path;
  }

  @override
  Future<String?> getCustomStorageRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(AppStorageKeys.downloadStorageDirectory)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> setCustomStorageRoot(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      await prefs.remove(AppStorageKeys.downloadStorageDirectory);
      return;
    }
    await prefs.setString(AppStorageKeys.downloadStorageDirectory, normalized);
  }

  @override
  Future<String?> pickDirectory() {
    return FilePicker.getDirectoryPath();
  }

  Future<bool> _canPrepare(io.Directory directory) async {
    try {
      await directory.create(recursive: true);
      final probe = io.File(p.join(directory.path, '.write_probe'));
      await probe.writeAsString('');
      if (await probe.exists()) {
        await probe.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
