import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';

class YamiboTagThreadPageData {
  const YamiboTagThreadPageData({
    required this.url,
    required this.tagId,
    required this.tagName,
    required this.threads,
    required this.pagination,
    this.moreUrl,
  });

  final String url;
  final String tagId;
  final String tagName;
  final List<YamiboTagThreadItem> threads;
  final YamiboTagPagePagination pagination;
  final String? moreUrl;
}

class YamiboTagThreadItem {
  const YamiboTagThreadItem({
    required this.tid,
    required this.threadUrl,
    required this.subject,
    this.forumName,
    this.forumUrl,
    this.forumId,
    this.authorName,
    this.authorUrl,
    this.authorId,
    this.createdAt,
    this.replyCount,
    this.viewCount,
    this.lastPosterName,
    this.lastPostUrl,
    this.lastPostAt,
    this.hasImageAttachment = false,
    this.hasAttachment = false,
  });

  final String tid;
  final String threadUrl;
  final String subject;
  final String? forumName;
  final String? forumUrl;
  final String? forumId;
  final String? authorName;
  final String? authorUrl;
  final String? authorId;
  final String? createdAt;
  final int? replyCount;
  final int? viewCount;
  final String? lastPosterName;
  final String? lastPostUrl;
  final String? lastPostAt;
  final bool hasImageAttachment;
  final bool hasAttachment;
}
