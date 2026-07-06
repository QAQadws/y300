import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/forum/domain/services/forum_chrome_image_adapter.dart';

void main() {
  const adapter = ForumChromeImageAdapter();
  const resolver = DefaultForumImageRequestResolver();

  test('carousel image maps to sticky forum head image request', () {
    final spec = adapter.carouselImage('https://bbs.yamibo.com/banner.jpg');
    final request = resolver.resolveCacheRequest(spec!);

    expect(spec.kind, ForumImageKind.forumHeadImage);
    expect(spec.ownerId, 'home');
    expect(spec.allowReaderOpen, isFalse);
    expect(request?.role, ImageCacheRole.forumHeadImage);
    expect(request?.ownerType, ImageCacheOwnerType.forum);
    expect(request?.ownerId, 'home');
    expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
  });

  test('forum head image maps to forum owner without reader open', () {
    final spec = adapter.headImage(
      fid: '33',
      imageUrl: 'https://bbs.yamibo.com/head.png',
    );
    final request = resolver.resolveCacheRequest(spec!);

    expect(spec.kind, ForumImageKind.forumHeadImage);
    expect(spec.ownerId, 'forum:33');
    expect(spec.allowReaderOpen, isFalse);
    expect(request?.role, ImageCacheRole.forumHeadImage);
    expect(request?.ownerId, 'forum:33');
    expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
  });

  test('forum icon maps to sticky forum icon request', () {
    final spec = adapter.forumIcon(
      fid: '30',
      imageUrl: 'https://bbs.yamibo.com/common_30_icon.gif',
    );
    final request = resolver.resolveCacheRequest(spec!);

    expect(spec.kind, ForumImageKind.forumIcon);
    expect(spec.ownerType, ImageCacheOwnerType.forumDisplay);
    expect(spec.ownerId, '30');
    expect(spec.allowReaderOpen, isFalse);
    expect(request?.role, ImageCacheRole.forumIcon);
    expect(request?.ownerType, ImageCacheOwnerType.forumDisplay);
    expect(request?.ownerId, '30');
    expect(request?.effectiveRetentionClass, ImageRetentionClass.sticky);
  });

  test('blank chrome image urls are ignored', () {
    expect(adapter.carouselImage(' '), isNull);
    expect(adapter.headImage(fid: '33', imageUrl: ''), isNull);
    expect(adapter.forumIcon(fid: '33', imageUrl: '  '), isNull);
  });
}
