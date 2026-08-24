import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void expectSourceNeutralFailure<T, C>(
  DataReadResult<T, C> result, {
  required DataReadFailureKind kind,
}) {
  expect(result, isA<DataReadFailure<T, C>>());
  final failure = result as DataReadFailure<T, C>;
  expect(failure.kind, kind);
  expect(failure.diagnosticMessage, isNotEmpty);
  expect(
    failure.diagnosticMessage,
    isNot(anyOf(contains('<html'), contains('Set-Cookie'))),
  );
}

final class ThreadRepositoryContractDriver {
  const ThreadRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.tid,
  });

  final String name;
  final ThreadRepository Function() createRepository;
  final String tid;
}

void runThreadRepositoryContractSuite(
  ThreadRepositoryContractDriver Function() createDriver,
) {
  group('ThreadRepository contract: ${createDriver().name}', () {
    test('returns stable ordered identities and provenance', () async {
      final driver = createDriver();
      final result = await driver.createRepository().getThreadDetail(
        tid: driver.tid,
      );
      final success =
          result
              as DataReadSuccess<
                ThreadDetailData,
                ThreadDetailReadCapabilities
              >;
      expect(success.data.tid, driver.tid);
      expect(success.data.posts, isNotEmpty);
      final pids = success.data.posts.map((post) => post.pid).toList();
      expect(pids.every((pid) => pid.trim().isNotEmpty), isTrue);
      expect(pids.toSet(), hasLength(pids.length));
      expect(
        success.capabilities.supports(ThreadDetailCapability.threadIdentity),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumDisplayRepositoryContractDriver {
  const ForumDisplayRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.fid,
  });

  final String name;
  final ForumDisplayRepository Function() createRepository;
  final String fid;
}

void runForumDisplayRepositoryContractSuite(
  ForumDisplayRepositoryContractDriver Function() createDriver,
) {
  group('ForumDisplayRepository contract: ${createDriver().name}', () {
    test('returns stable forum and topic identities with provenance', () async {
      final driver = createDriver();
      final result = await driver.createRepository().getForumDisplayByQuery(
        ForumDisplayQuery(fid: driver.fid),
      );
      final success =
          result
              as DataReadSuccess<
                ForumDisplayData,
                ForumDisplayReadCapabilities
              >;
      expect(success.data.fid, driver.fid);
      final tids = success.data.threads.map((thread) => thread.tid).toList();
      expect(tids.every((tid) => tid.trim().isNotEmpty), isTrue);
      expect(tids.toSet(), hasLength(tids.length));
      expect(
        success.capabilities.supports(ForumDisplayCapability.forumIdentity),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumDirectoryContractDriver {
  const ForumDirectoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumDirectoryRepository Function() createRepository;
}

void runForumDirectoryContractSuite(
  ForumDirectoryContractDriver Function() createDriver,
) {
  group('ForumDirectory contract: ${createDriver().name}', () {
    test('returns unique stable section and forum identities', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(
        const ForumDirectoryQuery(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumDirectoryData,
                ForumDirectoryReadCapabilities
              >;
      final sections = success.data.sections;
      final sectionIds = sections.map((section) => section.identity).toList();
      expect(sectionIds.every((id) => id.trim().isNotEmpty), isTrue);
      expect(sectionIds.toSet(), hasLength(sectionIds.length));
      final fids = sections
          .expand((section) => section.forums)
          .map((forum) => forum.fid)
          .toList();
      expect(fids.every((fid) => fid.trim().isNotEmpty), isTrue);
      expect(fids.toSet(), hasLength(fids.length));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ComicEpisodeCatalogContractDriver {
  const ComicEpisodeCatalogContractDriver({
    required this.name,
    required this.createRepository,
    required this.sourceTid,
  });

  final String name;
  final ComicEpisodeCatalogRepository Function() createRepository;
  final String sourceTid;
}

void runComicEpisodeCatalogContractSuite(
  ComicEpisodeCatalogContractDriver Function() createDriver,
) {
  group('ComicEpisodeCatalog contract: ${createDriver().name}', () {
    test('preserves source identity and ordered image references', () async {
      final driver = createDriver();
      final result = await driver.createRepository().loadCatalog(
        ComicEpisodeCatalogRequest(sourceTid: driver.sourceTid),
      );
      final success =
          result
              as DataReadSuccess<
                ComicEpisodeImageCatalog,
                ComicEpisodeCatalogCapabilities
              >;
      expect(success.data.sourceTid, driver.sourceTid);
      expect(success.data.images, isNotEmpty);
      expect(
        success.data.images.every((image) => image.url.trim().isNotEmpty),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ComicThreadDiscoveryContractDriver {
  const ComicThreadDiscoveryContractDriver({
    required this.name,
    required this.createRepository,
    required this.sourceTid,
  });

  final String name;
  final ComicThreadDiscoveryRepository Function() createRepository;
  final String sourceTid;
}

void runComicThreadDiscoveryContractSuite(
  ComicThreadDiscoveryContractDriver Function() createDriver,
) {
  group('ComicThreadDiscovery contract: ${createDriver().name}', () {
    test('returns only stable discovery identities', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(
        ComicThreadDiscoveryRequest(sourceTid: driver.sourceTid),
      );
      final success =
          result
              as DataReadSuccess<
                ComicThreadDiscoveryDocument,
                ComicThreadDiscoveryCapabilities
              >;
      expect(success.data.tid, driver.sourceTid);
      expect(success.data.fid, isNotEmpty);
      final pids = success.data.posts.map((post) => post.pid).toList();
      expect(pids.toSet(), hasLength(pids.length));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ThreadReplyPageContractDriver {
  const ThreadReplyPageContractDriver({
    required this.name,
    required this.createRepository,
    required this.tid,
    this.page = 1,
  });

  final String name;
  final ThreadReplyPageRepository Function() createRepository;
  final String tid;
  final int page;
}

void runThreadReplyPageContractSuite(
  ThreadReplyPageContractDriver Function() createDriver,
) {
  group('ThreadReplyPage contract: ${createDriver().name}', () {
    test('returns stable reply identities and page provenance', () async {
      final driver = createDriver();
      final result = await driver.createRepository().loadPage(
        tid: driver.tid,
        page: driver.page,
      );
      final success =
          result
              as DataReadSuccess<
                ThreadReplyPage,
                ThreadReplyPageReadCapabilities
              >;
      expect(success.data.tid, driver.tid);
      expect(success.data.page, driver.page);
      final pids = success.data.posts.map((post) => post.pid).toList();
      expect(pids.toSet(), hasLength(pids.length));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumTagDirectoryContractDriver {
  const ForumTagDirectoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ForumTagDirectoryRepository Function() createRepository;
  final ForumTagDirectoryQuery query;
}

void runForumTagDirectoryContractSuite(
  ForumTagDirectoryContractDriver Function() createDriver,
) {
  group('ForumTagDirectory contract: ${createDriver().name}', () {
    test('returns stable tag and ordered topic identities', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<
                ForumTagDirectoryData,
                ForumTagDirectoryReadCapabilities
              >;
      expect(success.data.tag.id, driver.query.tagId);
      final tids = success.data.topics.map((topic) => topic.tid).toList();
      expect(tids.every((tid) => tid.trim().isNotEmpty), isTrue);
      expect(tids.toSet(), hasLength(tids.length));
      expect(
        success.capabilities.supports(
          ForumTagDirectoryCapability.stableTagIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumSearchContractDriver {
  const ForumSearchContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ForumSearchRepository Function() createRepository;
  final ForumSearchQuery query;
}

void runForumSearchContractSuite(
  ForumSearchContractDriver Function() createDriver,
) {
  group('ForumSearch contract: ${createDriver().name}', () {
    test('returns ordered topic identities for the normalized query', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities>;
      expect(
        success.data.query.normalizedKeyword,
        driver.query.normalizedKeyword,
      );
      final tids = success.data.topics.map((topic) => topic.tid).toList();
      expect(tids.every((tid) => tid.trim().isNotEmpty), isTrue);
      expect(tids.toSet(), hasLength(tids.length));
      expect(
        success.capabilities.supports(
          ForumSearchCapability.stableTopicIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class FavoriteForumDirectoryContractDriver {
  const FavoriteForumDirectoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final FavoriteForumDirectoryRepository Function() createRepository;
}

void runFavoriteForumDirectoryContractSuite(
  FavoriteForumDirectoryContractDriver Function() createDriver,
) {
  group('FavoriteForumDirectory contract: ${createDriver().name}', () {
    test(
      'returns unique stable forum and remote favorite identities',
      () async {
        final result = await createDriver().createRepository().load(
          const FavoriteForumDirectoryQuery(),
        );
        final success =
            result
                as DataReadSuccess<
                  FavoriteForumDirectoryData,
                  FavoriteForumDirectoryReadCapabilities
                >;
        final fids = success.data.items.map((item) => item.fid).toList();
        final favids = success.data.items
            .map((item) => item.remoteFavoriteId)
            .whereType<String>()
            .toList();
        expect(fids.every((fid) => fid.trim().isNotEmpty), isTrue);
        expect(fids.toSet(), hasLength(fids.length));
        expect(favids.toSet(), hasLength(favids.length));
        expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
      },
    );
  });
}

final class FavoriteThreadDirectoryContractDriver {
  const FavoriteThreadDirectoryContractDriver({
    required this.name,
    required this.createRepository,
    this.page = 1,
  });

  final String name;
  final FavoriteThreadDirectoryRepository Function() createRepository;
  final int page;
}

void runFavoriteThreadDirectoryContractSuite(
  FavoriteThreadDirectoryContractDriver Function() createDriver,
) {
  group('FavoriteThreadDirectory contract: ${createDriver().name}', () {
    test('returns unique thread identities and coherent pagination', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(
        FavoriteThreadDirectoryQuery(page: driver.page),
      );
      final success =
          result
              as DataReadSuccess<
                FavoriteThreadDirectoryData,
                FavoriteThreadDirectoryReadCapabilities
              >;
      expect(success.data.pagination.currentPage, driver.page);
      final tids = success.data.items.map((item) => item.tid).toList();
      expect(tids.every((tid) => tid.trim().isNotEmpty), isTrue);
      expect(tids.toSet(), hasLength(tids.length));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class CurrentUserProfileContractDriver {
  const CurrentUserProfileContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final CurrentUserProfileRepository Function() createRepository;
}

void runCurrentUserProfileContractSuite(
  CurrentUserProfileContractDriver Function() createDriver,
) {
  group('CurrentUserProfile contract: ${createDriver().name}', () {
    test('returns a stable current-user identity', () async {
      final result = await createDriver().createRepository().load(
        const CurrentUserProfileQuery(),
      );
      final success =
          result
              as DataReadSuccess<
                CurrentUserProfileData,
                CurrentUserProfileReadCapabilities
              >;
      expect(success.data.identity.userId.trim(), isNotEmpty);
      expect(
        success.capabilities.supports(
          CurrentUserProfileCapability.stableUserIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumUserProfileContractDriver {
  const ForumUserProfileContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ForumUserProfileRepository Function() createRepository;
  final ForumUserProfileQuery query;
}

void runForumUserProfileContractSuite(
  ForumUserProfileContractDriver Function() createDriver,
) {
  group('ForumUserProfile contract: ${createDriver().name}', () {
    test('returns the requested stable user identity', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<
                ForumUserProfileData,
                ForumUserProfileReadCapabilities
              >;
      expect(success.data.identity.userId, driver.query.userId);
      expect(
        success.capabilities.supports(
          ForumUserProfileCapability.stableUserIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class UserBlogDirectoryContractDriver {
  const UserBlogDirectoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final UserBlogDirectoryRepository Function() createRepository;
  final UserBlogDirectoryQuery query;
}

void runUserBlogDirectoryContractSuite(
  UserBlogDirectoryContractDriver Function() createDriver,
) {
  group('UserBlogDirectory contract: ${createDriver().name}', () {
    test('returns stable feed, blog and owner identities', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<
                UserBlogDirectoryData,
                UserBlogDirectoryReadCapabilities
              >;
      expect(success.data.scope, driver.query.scope);
      final blogs = success.data.items;
      expect(blogs.map((item) => item.blogId).toSet(), hasLength(blogs.length));
      expect(blogs.every((item) => item.ownerUserId.trim().isNotEmpty), isTrue);
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class UserBlogDetailContractDriver {
  const UserBlogDetailContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final UserBlogDetailRepository Function() createRepository;
  final UserBlogDetailQuery query;
}

void runUserBlogDetailContractSuite(
  UserBlogDetailContractDriver Function() createDriver,
) {
  group('UserBlogDetail contract: ${createDriver().name}', () {
    test('returns the requested stable composite identity', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<
                UserBlogDetailData,
                UserBlogDetailReadCapabilities
              >;
      expect(success.data.blogId, driver.query.blogId);
      expect(success.data.ownerUserId, driver.query.ownerUserId);
      final commentIds = success.data.comments
          .map((comment) => comment.commentId)
          .toList();
      expect(commentIds.toSet(), hasLength(commentIds.length));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumHomeContractDriver {
  const ForumHomeContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumHomeRepository Function() createRepository;
}

void runForumHomeContractSuite(
  ForumHomeContractDriver Function() createDriver,
) {
  group('ForumHome contract: ${createDriver().name}', () {
    test('returns stable directory and ordered remote references', () async {
      final result = await createDriver().createRepository().loadHome(
        const ForumHomeQuery(),
      );
      final success =
          result
              as DataReadSuccess<ForumHomeDocument, ForumHomeReadCapabilities>;
      final fids = success.data.directory.sections
          .expand((section) => section.forums)
          .map((forum) => forum.fid)
          .toList();
      expect(fids.every((fid) => fid.trim().isNotEmpty), isTrue);
      expect(fids.toSet(), hasLength(fids.length));
      expect(
        success.capabilities.supports(ForumHomeCapability.forumDirectory),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumNotificationContractDriver {
  const ForumNotificationContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumNotificationRepository Function() createRepository;
}

void runForumNotificationContractSuite(
  ForumNotificationContractDriver Function() createDriver,
) {
  group('ForumNotification contract: ${createDriver().name}', () {
    test('returns unique ordered notification identities', () async {
      final result = await createDriver().createRepository().load(
        const ForumNotificationQuery(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumNotificationPage,
                ForumNotificationReadCapabilities
              >;
      final ids = success.data.items.map((item) => item.id).toList();
      expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        success.capabilities.values.supports(
          ForumNotificationCapability.stableIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumPrivateMessageContractDriver {
  const ForumPrivateMessageContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumPrivateMessageRepository Function() createRepository;
}

void runForumPrivateMessageContractSuite(
  ForumPrivateMessageContractDriver Function() createDriver,
) {
  group('ForumPrivateMessage contract: ${createDriver().name}', () {
    test('returns unique ordered message identities', () async {
      final result = await createDriver().createRepository().load(
        const ForumPrivateMessageQuery(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumPrivateMessagePage,
                ForumPrivateMessageReadCapabilities
              >;
      final ids = success.data.items.map((item) => item.messageId).toList();
      expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        success.capabilities.values.supports(
          ForumPrivateMessageCapability.stableIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ForumStickerCatalogContractDriver {
  const ForumStickerCatalogContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumStickerCatalogRepository Function() createRepository;
}

void runForumStickerCatalogContractSuite(
  ForumStickerCatalogContractDriver Function() createDriver,
) {
  group('ForumStickerCatalog contract: ${createDriver().name}', () {
    test('returns stable ordered groups and normalized codes', () async {
      final result = await createDriver().createRepository().load(
        const ForumStickerCatalogQuery(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumStickerCatalogData,
                ForumStickerCatalogReadCapabilities
              >;
      final groupIds = success.data.groups.map((group) => group.id).toList();
      expect(groupIds.every((id) => id.trim().isNotEmpty), isTrue);
      expect(groupIds.toSet(), hasLength(groupIds.length));
      expect(
        success.data.groups
            .expand((group) => group.items)
            .every((item) => item.insertionCode.trim().isNotEmpty),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ThreadPostRatingsContractDriver {
  const ThreadPostRatingsContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ThreadPostRatingsRepository Function() createRepository;
  final ThreadPostRatingsQuery query;
}

void runThreadPostRatingsContractSuite(
  ThreadPostRatingsContractDriver Function() createDriver,
) {
  group('ThreadPostRatings contract: ${createDriver().name}', () {
    test('returns ordered ratings for the requested post', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(driver.query);
      final success =
          result
              as DataReadSuccess<
                ThreadPostRatingsData,
                ThreadPostRatingsReadCapabilities
              >;
      expect(success.data.participantCount, success.data.ratings.length);
      expect(
        success.capabilities.values.supports(
          ThreadPostRatingsCapability.stablePostIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ThreadPostLocatorContractDriver {
  const ThreadPostLocatorContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ThreadPostLocatorRepository Function() createRepository;
  final ThreadPostLocationQuery query;
}

void runThreadPostLocatorContractSuite(
  ThreadPostLocatorContractDriver Function() createDriver,
) {
  group('ThreadPostLocator contract: ${createDriver().name}', () {
    test('returns exact matching thread and post identities', () async {
      final driver = createDriver();
      final result = await driver.createRepository().locate(driver.query);
      final success =
          result
              as DataReadSuccess<
                ThreadPostLocationData,
                ThreadPostLocatorReadCapabilities
              >;
      expect(success.data.tid, driver.query.tid);
      expect(success.data.pid, driver.query.pid);
      expect(success.data.page, greaterThan(0));
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}

final class ThreadAuthorPostContractDriver {
  const ThreadAuthorPostContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ThreadAuthorPostRepository Function() createRepository;
  final ThreadAuthorPostQuery query;
}

void runThreadAuthorPostContractSuite(
  ThreadAuthorPostContractDriver Function() createDriver,
) {
  group('ThreadAuthorPost contract: ${createDriver().name}', () {
    test(
      'returns only stable ordered posts for the requested author',
      () async {
        final driver = createDriver();
        final result = await driver.createRepository().load(driver.query);
        final success =
            result
                as DataReadSuccess<
                  ThreadAuthorPostPage,
                  ThreadAuthorPostReadCapabilities
                >;
        expect(success.data.tid, driver.query.tid);
        expect(success.data.currentPage, driver.query.page);
        final pids = success.data.posts.map((post) => post.pid).toList();
        expect(pids.every((pid) => pid.trim().isNotEmpty), isTrue);
        expect(pids.toSet(), hasLength(pids.length));
        expect(
          success.data.posts.every(
            (post) => post.authorId == driver.query.authorId,
          ),
          isTrue,
        );
        expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
      },
    );
  });
}
