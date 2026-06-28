import 'dart:io' as io;

import 'package:y300/features/cache/domain/services/protected_cover_cache_maintenance.dart';

/// Local filesystem adapter for protected cover maintenance.
///
/// Keeping dart:io behind this small data-layer adapter lets the cleanup
/// policy stay testable and avoids pulling platform file details into domain
/// services.
class LocalProtectedCoverFileStore implements ProtectedCoverFileStore {
  const LocalProtectedCoverFileStore();

  @override
  Future<bool> exists(String localPath) async {
    return io.File(localPath).exists();
  }

  @override
  Future<void> delete(String localPath) async {
    final file = io.File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
