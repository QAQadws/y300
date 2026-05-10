import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

abstract class DownloadStorageService {
  Future<DownloadStorageRoot> prepareRoot();

  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  });

  Future<io.Directory> prepareNovelDirectory({
    required String novelId,
    required String title,
  });

  String safeFileName(String value, {String fallback = 'untitled'});

  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  });

  Future<void> writeJsonAtomically(io.File file, Object? value);

  Future<void> writeFavoritesSnapshot(Map<String, Object?> json);

  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  });

  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({
    required String novelId,
    required String title,
    required String episodeId,
  });
}

class DefaultDownloadStorageService implements DownloadStorageService {
  DefaultDownloadStorageService({
    required StorageLocationRepository locationRepository,
    Random? random,
  })  : _locationRepository = locationRepository,
        _random = random ?? Random.secure();

  final StorageLocationRepository _locationRepository;
  final Random _random;

  @override
  Future<DownloadStorageRoot> prepareRoot() async {
    final custom = await _locationRepository.getCustomStorageRoot();
    final rootPath = custom ?? await _locationRepository.getDefaultStorageRoot();
    final root = io.Directory(rootPath);
    final comics = io.Directory(p.join(root.path, 'comics'));
    final novels = io.Directory(p.join(root.path, 'novels'));

    await _prepareDirectory(root);
    await _prepareDirectory(comics);
    await _prepareDirectory(novels);

    final favorites = io.File(p.join(root.path, 'favorites.json'));
    if (!await favorites.exists()) {
      await writeJsonAtomically(
        favorites,
        <String, Object?>{
          'schemaVersion': 1,
          'remoteCount': 0,
          'syncedAt': null,
          'threads': <Object?>[],
        },
      );
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
  }) async {
    final root = await prepareRoot();
    final directory = io.Directory(
      p.join(root.comicsPath, _workDirectoryName(title: title, id: workId)),
    );
    await _prepareDirectory(directory);
    return directory;
  }

  @override
  Future<io.Directory> prepareNovelDirectory({
    required String novelId,
    required String title,
  }) async {
    final root = await prepareRoot();
    final directory = io.Directory(
      p.join(root.novelsPath, _workDirectoryName(title: title, id: novelId)),
    );
    await _prepareDirectory(directory);
    await _prepareDirectory(io.Directory(p.join(directory.path, 'chapters')));
    await _prepareDirectory(io.Directory(p.join(directory.path, 'images')));
    return directory;
  }

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) {
    var normalized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[ .]+$'), '');
    if (normalized.isEmpty) {
      normalized = fallback;
    }
    if (normalized.length <= 80) {
      return normalized;
    }
    return '${normalized.substring(0, 64).trim()}-${_shortHash(value)}';
  }

  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) {
    final padded = (index + 1).toString().padLeft(3, '0');
    final cleanedTitle = safeFileName(title, fallback: 'chapter');
    final normalizedExtension = extension.startsWith('.') ? extension : '.$extension';
    return '$padded-$cleanedTitle$normalizedExtension';
  }

  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) async {
    await file.parent.create(recursive: true);
    final tmp = io.File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}');
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString('${encoder.convert(value)}\n', encoding: utf8);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) async {
    final root = await prepareRoot();
    await writeJsonAtomically(io.File(root.favoritesJsonPath), json);
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) async {
    final directory = await prepareComicDirectory(workId: workId, title: title);
    final meta = await _readJsonFile(io.File(p.join(directory.path, 'meta.json')));
    final chapters = meta?['chapters'];
    if (chapters is! List) {
      return null;
    }
    for (final chapter in chapters.whereType<Map>()) {
      if (chapter['episodeId'] != episodeId) {
        continue;
      }
      final cbzFile = chapter['cbzFile'] as String?;
      if (cbzFile == null || cbzFile.trim().isEmpty) {
        return null;
      }
      final cbz = io.File(p.join(directory.path, cbzFile));
      if (!await cbz.exists()) {
        return null;
      }
      final imageFiles = (chapter['imageFiles'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[];
      return DownloadedComicEpisode(
        workId: workId,
        episodeId: episodeId,
        cbzPath: cbz.path,
        imageFiles: imageFiles,
      );
    }
    return null;
  }

  @override
  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({
    required String novelId,
    required String title,
    required String episodeId,
  }) async {
    final directory = await prepareNovelDirectory(novelId: novelId, title: title);
    final meta = await _readJsonFile(io.File(p.join(directory.path, 'meta.json')));
    final chapters = meta?['chapters'];
    if (chapters is! List) {
      return null;
    }
    for (final chapter in chapters.whereType<Map>()) {
      if (chapter['episodeId'] != episodeId) {
        continue;
      }
      final relativePath = chapter['file'] as String?;
      if (relativePath == null || relativePath.trim().isEmpty) {
        return null;
      }
      final file = io.File(p.joinAll(<String>[
        directory.path,
        ...p.posix.split(relativePath),
      ]));
      if (!await file.exists()) {
        return null;
      }
      return DownloadedNovelChapter(
        novelId: novelId,
        episodeId: episodeId,
        chapterPath: file.path,
      );
    }
    return null;
  }

  String _workDirectoryName({
    required String title,
    required String id,
  }) {
    final name = safeFileName(title, fallback: 'work');
    return '$name-${_shortHash(id)}';
  }

  Future<void> _prepareDirectory(io.Directory directory) async {
    await directory.create(recursive: true);
    final marker = io.File(p.join(directory.path, '.nomedia'));
    if (!await marker.exists()) {
      await marker.writeAsString('');
    }
  }

  Future<Map<String, Object?>?> _readJsonFile(io.File file) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _shortHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }
}
