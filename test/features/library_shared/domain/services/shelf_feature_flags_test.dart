import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';

void main() {
  test('ShelfFeatureFlags can disable one shelf optimization at a time', () {
    final flags = ShelfFeatureFlags.defaults.copyWith(
      useShelfCoverQueue: false,
    );

    expect(flags.useShelfSnapshotQuery, isTrue);
    expect(flags.useShelfCoverQueue, isFalse);
    expect(flags.useShelfCoverImage, isTrue);
    expect(flags.useStaleWhileRevalidate, isTrue);
  });
}
