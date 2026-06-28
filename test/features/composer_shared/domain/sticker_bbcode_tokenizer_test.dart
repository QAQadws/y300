import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_bbcode_tokenizer.dart';

void main() {
  group('StickerBbCodeTokenizer', () {
    const tokenizer = StickerBbCodeTokenizer();
    final stickers = [
      _sticker(code: '{:9_656:}', imagePath: 'bugcat/Capoo16.gif'),
      _sticker(code: '{:1_1000:}', imagePath: 'default/handshake.gif'),
    ];

    test('encodes known sticker code into preview tag', () {
      expect(
        tokenizer.encodeForPreview('你好{:9_656:}', stickers),
        '你好[y300sticker]{:9_656:}[/y300sticker]',
      );
    });

    test('keeps unknown sticker-like code unchanged', () {
      expect(
        tokenizer.encodeForPreview('你好{:9_999:}', stickers),
        '你好{:9_999:}',
      );
    });

    test('encodes repeated and adjacent stickers', () {
      expect(
        tokenizer.encodeForPreview('{:9_656:}{:1_1000:}{:9_656:}', stickers),
        '[y300sticker]{:9_656:}[/y300sticker]'
        '[y300sticker]{:1_1000:}[/y300sticker]'
        '[y300sticker]{:9_656:}[/y300sticker]',
      );
    });

    test('does not break ordinary BBCode', () {
      expect(
        tokenizer.encodeForPreview('[b]{:9_656:}[/b]', stickers),
        '[b][y300sticker]{:9_656:}[/y300sticker][/b]',
      );
    });
  });
}

StickerItem _sticker({required String code, required String imagePath}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: ImageCacheKeys.remoteSmiley(imagePath),
  );
}
