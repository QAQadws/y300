import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

abstract interface class LibraryCoverStore {
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset);

  Future<io.File> fileFor(LibraryCoverAssetRef asset);

  Future<void> invalidate(LibraryCoverAssetRef asset);

  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  });

  Future<void> deleteAsset(String assetId);

  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset);

  Future<int> calculateUsageBytes();
}

class LibraryCoverDirectoryResolver {
  const LibraryCoverDirectoryResolver();

  Future<String> resolveRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = io.Directory(p.join(support.path, 'library_covers', 'v1'));
    await root.create(recursive: true);
    final marker = io.File(p.join(root.path, '.nomedia'));
    if (!await marker.exists()) {
      await marker.writeAsString('', flush: true);
    }
    return root.path;
  }
}

abstract interface class LibraryCoverDownloader {
  Future<void> download({required String url, required String targetPath});
}

class ForumResourceLibraryCoverDownloader implements LibraryCoverDownloader {
  ForumResourceLibraryCoverDownloader({
    required ForumResourceClient resourceClient,
    required ForumResourceReferenceResolver referenceResolver,
    required String referer,
  }) : _resourceClient = resourceClient,
       _referenceResolver = referenceResolver,
       _referer = referer,
       _queue = _SerialTaskQueue();

  final ForumResourceClient _resourceClient;
  final ForumResourceReferenceResolver _referenceResolver;
  final String _referer;
  final _SerialTaskQueue _queue;

  @override
  Future<void> download({required String url, required String targetPath}) {
    return _queue.run(() async {
      final reference = _referenceResolver.resolve(
        url,
        referer: Uri.tryParse(_referer),
      );
      if (reference == null) {
        throw StateError('Invalid cover resource reference');
      }
      final result = await _resourceClient.open(
        ForumResourceRequest(reference: reference),
      );
      if (result is! ForumResourceSuccess || result.statusCode == 304) {
        throw StateError('Cover resource request failed');
      }
      final file = await io.File(targetPath).open(mode: io.FileMode.writeOnly);
      try {
        await for (final chunk in result.content) {
          await file.writeFrom(chunk);
        }
        await file.flush();
      } finally {
        await file.close();
      }
    });
  }
}

class LocalLibraryCoverStore implements LibraryCoverStore {
  LocalLibraryCoverStore({
    required Future<String> rootPath,
    required LibraryCoverDownloader downloader,
  }) : _rootPath = rootPath,
       _downloader = downloader;

  final Future<String> _rootPath;
  final LibraryCoverDownloader _downloader;
  final Map<String, Future<io.File>> _ensureTasks = <String, Future<io.File>>{};

  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) {
    final existing = _ensureTasks[asset.versionedId];
    if (existing != null) {
      return existing;
    }
    late final Future<io.File> task;
    task = _ensureAvailable(asset).whenComplete(() {
      if (identical(_ensureTasks[asset.versionedId], task)) {
        _ensureTasks.remove(asset.versionedId);
      }
    });
    _ensureTasks[asset.versionedId] = task;
    return task;
  }

  Future<io.File> _ensureAvailable(LibraryCoverAssetRef asset) async {
    final target = await fileFor(asset);
    if (await target.exists()) {
      return target;
    }

    final legacyPath = asset.legacyLocalPath?.trim();
    if (legacyPath != null && legacyPath.isNotEmpty) {
      final legacy = io.File(legacyPath);
      if (await legacy.exists()) {
        await _atomicCopy(legacy, target);
        return target;
      }
    }

    final sourceUrl = asset.sourceUrl?.trim();
    if (sourceUrl == null || sourceUrl.isEmpty) {
      throw StateError('Cover asset is unavailable: ${asset.assetId}');
    }
    await target.parent.create(recursive: true);
    final temporary = io.File('${target.path}.part');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    try {
      await _downloader.download(url: sourceUrl, targetPath: temporary.path);
      await _commitTemporaryFile(temporary, target);
      await deleteOlderRevisions(asset);
      return target;
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  @override
  Future<io.File> fileFor(LibraryCoverAssetRef asset) async {
    final root = await _rootPath;
    final digest = _digest(asset.assetId);
    final kind = asset.kind == LibraryCoverAssetKind.custom
        ? 'custom'
        : 'source';
    return io.File(
      p.join(
        root,
        kind,
        digest.substring(0, 2),
        '$digest-r${asset.revision}.img',
      ),
    );
  }

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) async {
    final source = io.File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Cover source file does not exist: $sourcePath');
    }
    await _atomicCopy(source, await fileFor(asset));
  }

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {
    final file = await fileFor(asset);
    if (await file.exists()) {
      await file.delete();
    }
    final temporary = io.File('${file.path}.part');
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    final root = await _rootPath;
    final digest = _digest(assetId);
    for (final kind in const <String>['source', 'custom']) {
      final directory = io.Directory(
        p.join(root, kind, digest.substring(0, 2)),
      );
      if (!await directory.exists()) {
        continue;
      }
      await for (final entry in directory.list()) {
        if (entry is io.File && p.basename(entry.path).startsWith(digest)) {
          await entry.delete();
        }
      }
    }
  }

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) async {
    final current = await fileFor(asset);
    final directory = current.parent;
    if (!await directory.exists()) {
      return;
    }
    final digest = _digest(asset.assetId);
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! io.File || entry.path == current.path) {
        continue;
      }
      final name = p.basename(entry.path);
      if (name.startsWith('$digest-r') && !name.endsWith('.part')) {
        await entry.delete();
      }
    }
  }

  @override
  Future<int> calculateUsageBytes() async {
    final root = io.Directory(await _rootPath);
    if (!await root.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is io.File && !entry.path.endsWith('.part')) {
        total += await entry.length();
      }
    }
    return total;
  }

  Future<void> _atomicCopy(io.File source, io.File target) async {
    await target.parent.create(recursive: true);
    final temporary = io.File('${target.path}.part');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    final sink = temporary.openWrite();
    try {
      await source.openRead().pipe(sink);
      final file = await temporary.open(mode: io.FileMode.append);
      try {
        await file.flush();
      } finally {
        await file.close();
      }
      await _commitTemporaryFile(temporary, target);
    } catch (_) {
      await sink.close().catchError((Object _) {});
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  Future<void> _commitTemporaryFile(io.File temporary, io.File target) async {
    if (await target.exists()) {
      await temporary.delete();
      return;
    }
    await temporary.rename(target.path);
  }

  String _digest(String assetId) {
    return sha256.convert(utf8.encode(assetId)).toString();
  }
}

class _SerialTaskQueue {
  bool _running = false;
  final List<Future<void> Function()> _queue = <Future<void> Function()>[];

  Future<void> run(Future<void> Function() action) {
    final completer = Completer<void>();
    _queue.add(() async {
      try {
        await action();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _drain();
    return completer.future;
  }

  void _drain() {
    if (_running || _queue.isEmpty) {
      return;
    }
    _running = true;
    final action = _queue.removeAt(0);
    unawaited(
      action().whenComplete(() {
        _running = false;
        _drain();
      }),
    );
  }
}
