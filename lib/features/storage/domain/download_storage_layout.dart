import 'package:path/path.dart' as p;
import 'package:y300/features/storage/domain/download_storage_models.dart';

abstract final class DownloadStorageLayout {
  static DownloadStorageRoot resolve(String rootPath) {
    final normalizedRoot = p.normalize(rootPath);
    return DownloadStorageRoot(
      path: normalizedRoot,
      comicsPath: p.join(normalizedRoot, 'comics'),
      novelsPath: p.join(normalizedRoot, 'novels'),
      favoritesJsonPath: p.join(normalizedRoot, 'favorites.json'),
    );
  }

  static Map<String, Object?> emptyFavoritesSnapshot() {
    return <String, Object?>{
      'schemaVersion': 1,
      'remoteCount': 0,
      'syncedAt': null,
      'threads': <Object?>[],
    };
  }
}
