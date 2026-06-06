import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/domain/services/sticker_code_normalizer.dart';

void main() {
  group('StickerCodeNormalizer', () {
    const normalizer = StickerCodeNormalizer();

    test('normalizes escaped bugcat sticker pattern', () {
      expect(normalizer.normalize(r'/\{\:9_656\:\}/'), '{:9_656:}');
    });

    test('normalizes escaped default sticker pattern', () {
      expect(normalizer.normalize(r'/\{\:1_1000\:\}/'), '{:1_1000:}');
    });

    test('keeps plain code stable', () {
      expect(normalizer.normalize('{:9_656:}'), '{:9_656:}');
    });
  });
}
