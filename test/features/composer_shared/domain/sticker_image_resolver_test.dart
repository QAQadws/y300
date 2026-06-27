import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_image_resolver.dart';

void main() {
  group('StickerImageResolver', () {
    const resolver = StickerImageResolver();

    test('normalizes API path, HTML src and absolute URL to one cache key', () {
      final fromApi = resolver.resolve('comcom/2.gif');
      final fromHtml = resolver.resolve('static/image/smiley/comcom/2.gif');
      final fromAbsolute = resolver.resolve(
        'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif?from=post',
      );

      expect(fromApi.normalizedPath, 'comcom/2.gif');
      expect(fromHtml.normalizedPath, fromApi.normalizedPath);
      expect(fromAbsolute.normalizedPath, fromApi.normalizedPath);
      expect(fromHtml.cacheKey, fromApi.cacheKey);
      expect(fromAbsolute.cacheKey, fromApi.cacheKey);
      expect(
        fromApi.url,
        'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
      );
    });
  });
}
