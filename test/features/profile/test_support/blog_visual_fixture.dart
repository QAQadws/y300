import 'dart:async';

import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

const blogVisualTitle = '雨后散步：记录街角的树、书店与难得的晴天';
const blogVisualAuthor = '一位名字很长很长的日志作者';
const blogVisualAvatar = 'https://example.test/uc_server/images/noavatar.svg';
const blogVisualImage = 'https://example.test/data/attachment/home/fixture.png';

final class BlogVisualDirectory implements UserBlogDirectoryRepository {
  bool empty = false;
  Completer<void>? gate;
  DataReadFailureKind? failure;

  @override
  final capabilities = UserBlogDirectorySourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDirectoryCapability.values),
    paginationPrecision: PaginationPrecision.exact,
  );

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    await gate?.future;
    if (failure != null) {
      return DataReadFailure(
        kind: failure!,
        diagnosticMessage: 'visual fixture',
      );
    }
    return DataReadSuccess(
      data: UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        categories: const [UserBlogCategory(id: '3', name: '日常与阅读')],
        items: empty
            ? const []
            : [
                for (var i = 0; i < 3; i++)
                  UserBlogSummary(
                    blogId: '${11 + i}',
                    ownerUserId: '101',
                    title: i == 0 ? blogVisualTitle : '第 ${i + 1} 篇生活随记',
                    authorName: blogVisualAuthor,
                    avatarUrl: blogVisualAvatar,
                    publishedAtText: '2026-09-12 10:30',
                    excerpt: '雨后的空气很清新。在街角停下来，读一会儿书，记录生活中值得记住的小事。',
                    categoryNames: const ['日常与阅读'],
                    actions: const {UserBlogAction.edit, UserBlogAction.delete},
                  ),
              ],
        pagination: UserBlogPagination(currentPage: query.page, totalPages: 1),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

final class BlogVisualDetail implements UserBlogDetailRepository {
  bool withImage = false;
  @override
  final capabilities = UserBlogDetailSourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
  );

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async => DataReadSuccess(
    data: UserBlogDetailData(
      ownerUserId: query.ownerUserId,
      blogId: query.blogId,
      title: blogVisualTitle,
      authorName: blogVisualAuthor,
      avatarUrl: blogVisualAvatar,
      publishedAtText: '2026-09-12 10:30',
      viewCount: 128,
      commentCount: 2,
      bodyHtml:
          '<p>雨后的空气很清新。<strong>记录生活</strong>，也给自己留一点安静的时间。</p>'
          '<blockquote>慢慢走，看看路边的树。</blockquote>'
          '${withImage ? '<img src="$blogVisualImage" width="240" height="100">' : ''}'
          '<p><a href="https://example.test/reading">一份阅读笔记</a></p>',
      commentsOpen: true,
      actions: const {UserBlogAction.edit, UserBlogAction.delete},
      comments: const [
        UserBlogComment(
          commentId: '31',
          authorName: blogVisualAuthor,
          authorUserId: '202',
          avatarUrl: blogVisualAvatar,
          publishedAtText: '2026-09-12 11:45',
          bodyHtml: '<p>喜欢这样的散步。<em>下次也带一本书吧。</em></p>',
          actions: {UserBlogCommentAction.reply},
        ),
        UserBlogComment(
          commentId: '32',
          authorName: '匿名读者',
          bodyHtml: '<p>谢谢分享这段日常。</p>',
        ),
      ],
    ),
    capabilities: capabilities.toReadCapabilities(),
    metadata: const DataReadMetadata.network(),
  );
}

final class BlogVisualPreferences
    implements ForumHtmlReaderPreferencesRepository {
  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults();
  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}
