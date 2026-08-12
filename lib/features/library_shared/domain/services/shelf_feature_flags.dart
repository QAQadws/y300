/// Runtime switches for the shelf optimization path.
///
/// The flags are intentionally plain Dart values so tests and future settings
/// screens can override one capability at a time without coupling shared shelf
/// code to Riverpod or SharedPreferences.
class ShelfFeatureFlags {
  const ShelfFeatureFlags({
    this.useShelfSnapshotQuery = true,
    this.useShelfCoverImage = true,
    this.useStaleWhileRevalidate = true,
  });

  final bool useShelfSnapshotQuery;
  final bool useShelfCoverImage;
  final bool useStaleWhileRevalidate;

  static const ShelfFeatureFlags defaults = ShelfFeatureFlags();

  ShelfFeatureFlags copyWith({
    bool? useShelfSnapshotQuery,
    bool? useShelfCoverImage,
    bool? useStaleWhileRevalidate,
  }) {
    return ShelfFeatureFlags(
      useShelfSnapshotQuery:
          useShelfSnapshotQuery ?? this.useShelfSnapshotQuery,
      useShelfCoverImage: useShelfCoverImage ?? this.useShelfCoverImage,
      useStaleWhileRevalidate:
          useStaleWhileRevalidate ?? this.useStaleWhileRevalidate,
    );
  }
}
