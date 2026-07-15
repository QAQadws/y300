import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';

void main() {
  group('ComicReaderFeatureFlags', () {
    test('defaults keep active comic capabilities stable', () {
      const flags = ComicReaderFeatureFlags.defaults;

      expect(flags.readerStrictCompleteRead, isTrue);
      expect(flags.readerCustomMetadataEnabled, isTrue);
      expect(flags.readerRefreshMultiKeywordEnabled, isFalse);
    });

    test('copyWith can disable an active capability independently', () {
      final flags = ComicReaderFeatureFlags.defaults.copyWith(
        readerStrictCompleteRead: false,
      );

      expect(flags.readerStrictCompleteRead, isFalse);
      expect(flags.readerCustomMetadataEnabled, isTrue);
      expect(flags.readerRefreshMultiKeywordEnabled, isFalse);
    });
  });
}
