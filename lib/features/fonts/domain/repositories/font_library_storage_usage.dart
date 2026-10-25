/// Read-only accounting for persistent files owned by the local font library.
abstract interface class FontLibraryStorageUsage {
  /// Counts actual regular-file bytes without loading or repairing font data.
  Future<int> calculateUsageBytes();
}
