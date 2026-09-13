import 'dart:async';
import 'dart:io' as io;
import 'package:path/path.dart' as p;

/// Retires only the old implementation's temporary files. Persistent covers
/// are outside this root and never participate in this upgrade cleanup.
class LibraryCoverLegacyThumbnailCleanup {
  LibraryCoverLegacyThumbnailCleanup({
    required Future<String> Function() rootPath,
    this.batchSize = 32,
  }) : _rootPath = rootPath;
  final Future<String> Function() _rootPath;
  final int batchSize;
  bool _disposed = false;
  Future<void>? _running;
  Future<void> run() => _running ??= _clean();
  Future<void> _clean() async {
    final root = io.Directory(await _rootPath());
    if (!await root.exists()) return;
    var count = 0;
    await for (final asset in root.list(followLinks: false)) {
      if (_disposed) return;
      if (asset is! io.Directory ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(p.basename(asset.path))) {
        continue;
      }
      await for (final file in asset.list(followLinks: false)) {
        if (_disposed) return;
        if (file is! io.File ||
            !RegExp(
              r'^r[0-9]+-[0-9]+x[0-9]+\.png(?:\.[0-9]+\.part)?$',
            ).hasMatch(p.basename(file.path))) {
          continue;
        }
        try {
          await file.delete();
        } on io.FileSystemException {
          /* Retry next startup. */
        }
        if (++count % batchSize == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
  }
}
