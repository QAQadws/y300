import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('TallImagePolicy', () {
    test('detects Mihon-like tall image candidates', () {
      const policy = TallImagePolicy.mihonLike;

      expect(
        policy.shouldSplit(
          imageWidth: 1000,
          imageHeight: 5000,
          viewportMainAxisExtent: 1000,
        ),
        isTrue,
      );
      expect(
        policy.shouldSplit(
          imageWidth: 1000,
          imageHeight: 2500,
          viewportMainAxisExtent: 1000,
        ),
        isFalse,
      );
    });

    test('disabled tall image policy never splits', () {
      expect(
        TallImagePolicy.disabled.shouldSplit(
          imageWidth: 1000,
          imageHeight: 8000,
          viewportMainAxisExtent: 1000,
        ),
        isFalse,
      );
    });
  });
}
