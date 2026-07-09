import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';

void main() {
  test(
    'normalized URL keys are stable across query order and scheme casing',
    () {
      final first = ImageCacheKeys.threadInline(
        'HTTPS://bbs.yamibo.com/data/attachment/forum/page.jpg?b=2&a=1#frag',
      );
      final second = ImageCacheKeys.threadInline(
        'https://bbs.yamibo.com/data/attachment/forum/page.jpg?a=1&b=2',
      );

      expect(first, second);
      expect(first, startsWith('thread/inline/'));
      expect(first, endsWith('/page.jpg'));
    },
  );

  test(
    'remote smiley keys normalize html src, absolute url and api image path',
    () {
      final fromHtml = ImageCacheKeys.remoteSmiley(
        'static/image/smiley/comcom/2.gif',
      );
      final fromAbsolute = ImageCacheKeys.remoteSmiley(
        'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif?from=post',
      );
      final fromApi = ImageCacheKeys.remoteSmiley('comcom/2.gif');

      expect(fromHtml, fromAbsolute);
      expect(fromHtml, fromApi);
      expect(fromHtml, startsWith('smiley/'));
      expect(fromHtml, endsWith('/2.gif'));
    },
  );

  test('malformed percent encoded paths still produce safe cache keys', () {
    final key = ImageCacheKeys.threadInline('https://img.test/forum/%E3.jpg');

    expect(key, startsWith('thread/inline/'));
    expect(key, endsWith('/_E3.jpg'));
  });
}
