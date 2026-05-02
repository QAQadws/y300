import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

/// Resolves the effective comic cache directory from persisted settings.
///
/// Rules:
/// 1. If custom directory is set, use `<custom>/y300_comic_cache`.
/// 2. Otherwise use `<temporary>/y300_comic_cache`.
class ComicCacheDirectoryResolver {
  const ComicCacheDirectoryResolver();

  static const String cacheFolderName = 'y300_comic_cache';

  Future<String> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(AppStorageKeys.comicCacheDirectory)?.trim();
    final basePath = (custom == null || custom.isEmpty)
        ? (await getTemporaryDirectory()).path
        : custom;
    final path = p.join(basePath, cacheFolderName);
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory.path;
  }
}

