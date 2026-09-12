import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// In-memory articles and comment pages for navigation, without network assets.
final class BlogDetailFixture implements UserBlogDetailRepository {
  final queries = <UserBlogDetailQuery>[];
  String bodyHtml = '<p>article fixture</p>';
  String commentHtml = '<p>comment fixture</p>';
  String? title;
  String authorName = 'fixture author';
  String? publishedAtText;
  List<UserBlogCategoryLink> categoryLinks = const [];
  bool emptyComments = false;
  @override
  final capabilities = UserBlogDetailSourceCapabilities(
    values: DataCapabilitySet.from(supported: UserBlogDetailCapability.values),
  );

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    final page = query.lastCommentPage ? 9 : query.page;
    return DataReadSuccess(
      data: UserBlogDetailData(
        ownerUserId: query.ownerUserId,
        blogId: query.blogId,
        title: title ?? 'Article ${query.blogId}',
        bodyHtml: bodyHtml,
        authorName: authorName,
        publishedAtText: publishedAtText,
        categoryLinks: categoryLinks,
        commentsOpen: true,
        commentPagination: UserBlogPagination(
          currentPage: page,
          totalPages: 9,
          hasPrevious: page > 1,
          hasNext: query.commentId == null && page < 9,
        ),
        comments: emptyComments
            ? const []
            : [
                UserBlogComment(
                  commentId: query.commentId ?? '31',
                  authorName: 'comment author',
                  bodyHtml: commentHtml,
                ),
              ],
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
