import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';

void main() {
  group('ComicReaderFeatureFlags', () {
    test('defaults keep Phase 10 safe rollout switches enabled', () {
      const flags = ComicReaderFeatureFlags.defaults;

      expect(flags.readerStrictCompleteRead, isTrue);
      expect(flags.readerPreloadQueueEnabled, isTrue);
      expect(flags.readerNextChapterPreloadEnabled, isTrue);
      expect(flags.readerCustomMetadataEnabled, isTrue);
      expect(flags.readerRefreshMultiKeywordEnabled, isFalse);
    });

    test('copyWith can disable one reader capability at a time', () {
      final flags = ComicReaderFeatureFlags.defaults.copyWith(
        readerPreloadQueueEnabled: false,
      );

      expect(flags.readerStrictCompleteRead, isTrue);
      expect(flags.readerPreloadQueueEnabled, isFalse);
      expect(flags.readerNextChapterPreloadEnabled, isTrue);
      expect(flags.readerCustomMetadataEnabled, isTrue);
      expect(flags.readerRefreshMultiKeywordEnabled, isFalse);
    });
  });
}
