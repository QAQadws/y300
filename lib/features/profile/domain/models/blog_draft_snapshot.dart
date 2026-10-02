import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Local source values for one account's unpublished journal, without secrets.
final class BlogDraftSnapshot {
  const BlogDraftSnapshot({
    required this.accountId,
    required this.updatedAt,
    this.subject = '',
    this.bodyHtml = '',
    this.tags = '',
    this.siteCategoryId = '0',
    this.personalCategoryId = '0',
    this.newPersonalCategory = '',
    this.creatingCategory = false,
    this.publishFeed = false,
    this.visibility = UserBlogVisibility.public,
    this.commentsEnabled = true,
    this.targetNames = '',
    this.images = const [],
    this.pendingSubmission = false,
  });

  final String accountId;
  final DateTime updatedAt;
  final String subject;
  final String bodyHtml;
  final String tags;
  final String siteCategoryId;
  final String personalCategoryId;
  final String newPersonalCategory;
  final bool creatingCategory;
  final bool publishFeed;
  final UserBlogVisibility visibility;
  final bool commentsEnabled;
  final String targetNames;
  final List<BlogDraftImage> images;
  final bool pendingSubmission;
}

/// A lookup hint, never an ownership proof or an upload retry request.
final class BlogDraftImage {
  const BlogDraftImage({required this.picId, required this.originalUri});
  final String picId;
  final Uri originalUri;
}

final class BlogDraftUsage {
  const BlogDraftUsage({required this.count, required this.bytes});
  final int count;
  final int bytes;
}
