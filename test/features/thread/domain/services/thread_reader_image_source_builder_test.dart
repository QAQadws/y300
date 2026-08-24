import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/services/thread_reader_image_source_builder.dart';

void main() {
  test('buildFromPost maps thread images to reader cache sources', () {
    const builder = ThreadReaderImageSourceBuilder(
      imageSourcePipeline: DefaultForumImageSourcePipeline(),
    );
    final post = ThreadPost(
      pid: '41520485',
      author: '作者',
      authorId: '448216',
      message:
          '<img file="data/attachment/forum/202606/01/body.jpg" />'
          '<img src="static/image/smiley/comcom/2.gif" />',
      number: 2,
      isFirst: false,
      dateline: '2026-06-01',
      attachmentImages: const <ForumPostAttachmentImage>[
        ForumPostAttachmentImage(
          aid: '1597001',
          url: 'https://bbs.yamibo.com/data/attachment/forum/202606/02',
          attachment: 'attach.png',
          filename: 'attach.png',
          attachimg: '1',
          ext: 'png',
        ),
      ],
    );

    final sources = builder.buildFromPost(post: post, tid: '570068');

    expect(sources, hasLength(2));
    expect(sources[0].ownerType, ImageCacheOwnerType.thread);
    expect(sources[0].ownerId, '570068');
    expect(sources[0].role, ImageCacheRole.threadInline);
    expect(sources[0].retentionClass, ImageRetentionClass.ephemeral);
    expect(
      sources[0].cacheKey,
      ImageCacheKeys.threadInline(
        'https://bbs.yamibo.com/data/attachment/forum/202606/01/body.jpg',
      ),
    );

    expect(sources[1].role, ImageCacheRole.threadAttachment);
    expect(
      sources[1].cacheKey,
      ImageCacheKeys.threadAttachment(
        'https://bbs.yamibo.com/data/attachment/forum/202606/02/attach.png',
      ),
    );
    expect(sources[1].toCacheRequest().cacheKey, sources[1].cacheKey);
    expect(
      sources[1]
          .toCacheRequest(retentionOverride: ImageRetentionClass.recentReader)
          .retentionClass,
      ImageRetentionClass.recentReader,
    );
  });
}
