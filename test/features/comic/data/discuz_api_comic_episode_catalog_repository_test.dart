import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/data/repositories/discuz_api_comic_episode_catalog_repository.dart';
import 'package:y300/features/comic/domain/models/comic_episode_image_catalog.dart';
import 'package:y300/features/comic/domain/repositories/comic_episode_catalog_repository.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

import '../../../support/data_source_contracts/data_read_contract_scenarios.dart';
import '../../../support/data_source_contracts/comic_episode_catalog_contract_suite.dart';

void main() {
  runComicEpisodeCatalogContractSuite(
    () => ComicEpisodeCatalogContractDriver(
      name: 'Discuz v4 thread adapter',
      createRepository: () => DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: _ThreadRepository(
          _detail(
            post: ThreadPost(
              pid: 'p1',
              author: 'author',
              authorId: '1',
              message: '<img src="https://img.test/1.jpg">',
              number: 1,
              isFirst: true,
              dateline: 'today',
            ),
          ),
        ),
        imageSourcePipeline: const DefaultForumImageSourcePipeline(),
      ),
      sourceTid: '100',
    ),
  );

  test(
    'keeps DOM-first order and attachment identity without duplicates',
    () async {
      final repository = DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: _ThreadRepository(
          _detail(
            post: ThreadPost(
              pid: 'p1',
              author: 'author',
              authorId: '1',
              message:
                  '<img src="https://bbs.yamibo.com/data/attachment/forum/a.jpg">',
              number: 1,
              isFirst: true,
              dateline: 'today',
              attachmentImages: const <ForumPostAttachmentImage>[
                ForumPostAttachmentImage(
                  aid: '1',
                  url: '',
                  attachment: 'data/attachment/forum/a.jpg',
                  filename: 'a.jpg',
                  attachimg: '1',
                  ext: 'jpg',
                ),
                ForumPostAttachmentImage(
                  aid: '2',
                  url: '',
                  attachment: 'data/attachment/forum/b.jpg',
                  filename: 'b.jpg',
                  attachimg: '1',
                  ext: 'jpg',
                ),
              ],
            ),
          ),
        ),
        imageSourcePipeline: const DefaultForumImageSourcePipeline(),
      );

      final result = await repository.loadCatalog(
        const ComicEpisodeCatalogRequest(sourceTid: '100'),
      );

      expectSuccessfulReadContract(
        result,
        hasKnownIdentity: (capabilities) => capabilities.supports(
          ComicEpisodeCatalogCapability.reliableFirstPostIdentity,
        ),
      );
      final images = result.dataOrNull!.images;
      expect(images, hasLength(2));
      expect(images.first.origin, ComicEpisodeImageOrigin.dom);
      expect(images.last.origin, ComicEpisodeImageOrigin.attachment);
      expect(images.last.attachmentId, '2');
    },
  );

  test(
    'an identified first post with no images is a successful empty catalog',
    () async {
      final repository = DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: _ThreadRepository(
          _detail(post: _post(number: 1, isFirst: true)),
        ),
        imageSourcePipeline: const DefaultForumImageSourcePipeline(),
      );

      final result = await repository.loadCatalog(
        const ComicEpisodeCatalogRequest(sourceTid: '100'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.images, isEmpty);
    },
  );

  test('missing first-post identity fails closed', () async {
    final repository = DiscuzApiComicEpisodeCatalogRepository(
      threadRepository: _ThreadRepository(
        _detail(post: _post(number: 2, isFirst: false)),
      ),
      imageSourcePipeline: const DefaultForumImageSourcePipeline(),
    );

    final result = await repository.loadCatalog(
      const ComicEpisodeCatalogRequest(sourceTid: '100'),
    );

    expectSourceNeutralFailure(result, kind: DataReadFailureKind.parse);
  });
}

final class _ThreadRepository implements ThreadRepository {
  const _ThreadRepository(this.detail);

  final ThreadDetailData detail;

  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    return DataReadSuccess(
      data: detail,
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

ThreadDetailData _detail({required ThreadPost post}) {
  return ThreadDetailData(
    tid: '100',
    fid: '30',
    subject: 'episode',
    author: 'author',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[post],
  );
}

ThreadPost _post({required int number, required bool isFirst}) {
  return ThreadPost(
    pid: 'p$number',
    author: 'author',
    authorId: '1',
    message: '<p>text</p>',
    number: number,
    isFirst: isFirst,
    dateline: 'today',
  );
}
