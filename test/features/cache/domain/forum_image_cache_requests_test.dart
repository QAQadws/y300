import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  test('unused composer thumbnails use an isolated clearable cache role', () {
    final request = ForumImageCacheRequests.composerUnusedAttachment(
      aid: ' 123456 ',
      url: 'https://bbs.yamibo.com/forum.php?mod=image&aid=123456&key=secret',
    );

    expect(request.cacheKey, 'composer/unused/123456');
    expect(request.ownerType, ImageCacheOwnerType.composer);
    expect(request.ownerId, '123456');
    expect(request.role, ImageCacheRole.composerUnusedAttachment);
    expect(request.effectiveRetentionClass, ImageRetentionClass.ephemeral);
    expect(request.cacheKey, isNot(contains('secret')));
  });
}
