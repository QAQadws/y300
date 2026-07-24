import 'package:y300/core/utils/parse_utils.dart';

class ForumPostAttachmentImage {
  const ForumPostAttachmentImage({
    required this.aid,
    required this.url,
    required this.attachment,
    required this.filename,
    required this.attachimg,
    required this.ext,
  });

  final String aid;
  final String url;
  final String attachment;
  final String filename;
  final String attachimg;
  final String ext;

  factory ForumPostAttachmentImage.fromJson(JsonMap json) {
    return ForumPostAttachmentImage(
      aid: ParseUtils.asString(json['aid']),
      url: ParseUtils.asString(json['url']),
      attachment: ParseUtils.asString(json['attachment']),
      filename: ParseUtils.asString(json['filename']),
      attachimg: ParseUtils.asString(json['attachimg']),
      ext: ParseUtils.asString(json['ext']),
    );
  }
}

class ThreadPollOption {
  const ThreadPollOption({
    required this.id,
    required this.label,
    this.voteCount,
    this.percent,
    this.colorHex,
  });

  final String id;
  final String label;
  final int? voteCount;
  final double? percent;
  final String? colorHex;
}

class ThreadPoll {
  const ThreadPoll({
    required this.isMultipleChoice,
    required this.summary,
    required this.options,
    this.canVote = true,
    this.maxChoices,
    this.deadlineText,
    this.actionUrl,
    this.formHash,
    this.statusText,
  });

  final bool isMultipleChoice;
  final bool canVote;
  final int? maxChoices;
  final String summary;
  final String? deadlineText;
  final String? actionUrl;
  final String? formHash;
  final String? statusText;
  final List<ThreadPollOption> options;
}

class ThreadPostRating {
  const ThreadPostRating({
    required this.userName,
    required this.score,
    required this.reason,
    this.userId,
    this.avatarUrl,
    this.dateline,
  });

  final String userName;
  final String score;
  final String reason;
  final String? userId;
  final String? avatarUrl;
  final String? dateline;
}

class ThreadPostRatingSummary {
  const ThreadPostRatingSummary({
    required this.participantText,
    required this.scoreText,
    required this.ratings,
    this.viewAllUrl,
  });

  final String participantText;
  final String scoreText;
  final List<ThreadPostRating> ratings;
  final String? viewAllUrl;
}

class ThreadPostTagLink {
  const ThreadPostTagLink({required this.label, required this.url, this.tagId});

  final String label;
  final String url;
  final String? tagId;
}

class ThreadPostCommentEntry {
  const ThreadPostCommentEntry({
    required this.author,
    required this.message,
    required this.dateline,
    this.authorId,
    this.authorUrl,
    this.avatarUrl,
  });

  final String author;
  final String message;
  final String dateline;
  final String? authorId;
  final String? authorUrl;
  final String? avatarUrl;
}

class ThreadPost {
  ThreadPost({
    required this.pid,
    required this.author,
    required this.authorId,
    required this.message,
    required this.number,
    required this.isFirst,
    required this.dateline,
    this.avatarUrl,
    this.replyUrl,
    this.rateUrl,
    this.commentUrl,
    this.rateSummary,
    this.ratingSummary,
    this.poll,
    this.tagLinks = const <ThreadPostTagLink>[],
    this.comments = const <ThreadPostCommentEntry>[],
    this.attachmentImages = const <ForumPostAttachmentImage>[],
  });

  final String pid;
  final String author;
  final String authorId;
  final String message;
  final int number;
  final bool isFirst;
  final String dateline;
  final String? avatarUrl;
  final String? replyUrl;
  final String? rateUrl;
  final String? commentUrl;
  final String? rateSummary;
  final ThreadPostRatingSummary? ratingSummary;
  final ThreadPoll? poll;
  final List<ThreadPostTagLink> tagLinks;
  final List<ThreadPostCommentEntry> comments;

  /// Raw Discuz attachment metadata. Entries may be images or non-image files.
  final List<ForumPostAttachmentImage> attachmentImages;

  factory ThreadPost.fromJson(JsonMap json) {
    return ThreadPost(
      pid: ParseUtils.asString(json['pid']),
      author: ParseUtils.asString(json['author']),
      authorId: ParseUtils.asString(json['authorid']),
      message: ParseUtils.asString(json['message']),
      number: ParseUtils.asInt(json['number']),
      isFirst: ParseUtils.asString(json['first']) == '1',
      dateline: ParseUtils.asString(json['dateline']),
      attachmentImages: _parseAttachmentImages(json['attachments']),
    );
  }

  static List<ForumPostAttachmentImage> _parseAttachmentImages(dynamic value) {
    final attachments = ParseUtils.asMap(value);
    if (attachments.isEmpty) {
      return const <ForumPostAttachmentImage>[];
    }
    return attachments.values
        .map(ParseUtils.asMap)
        .where((item) => item.isNotEmpty)
        .map(ForumPostAttachmentImage.fromJson)
        .where((item) => item.attachment.trim().isNotEmpty)
        .toList(growable: false);
  }
}

class ThreadDetailData {
  ThreadDetailData({
    required this.tid,
    required this.fid,
    this.typeid = '',
    this.typeName,
    this.forumName,
    this.forumUrl,
    required this.subject,
    required this.author,
    required this.replies,
    required this.views,
    required this.currentPage,
    required this.perPage,
    required this.posts,
    this.lastPage,
    this.previousPageUrl,
    this.nextPageUrl,
    this.reverseOrderUrl,
    this.onlyAuthorUrl,
    this.favoriteUrl,
    this.shareUrl,
    this.homeUrl,
    this.desktopUrl,
  });

  final String tid;
  final String fid;
  final String typeid;
  final String? typeName;
  final String? forumName;
  final String? forumUrl;
  final String subject;
  final String author;
  final int replies;
  final int views;
  final int currentPage;
  final int perPage;
  final List<ThreadPost> posts;
  final int? lastPage;
  final String? previousPageUrl;
  final String? nextPageUrl;
  final String? reverseOrderUrl;
  final String? onlyAuthorUrl;
  final String? favoriteUrl;
  final String? shareUrl;
  final String? homeUrl;
  final String? desktopUrl;

  /// Discuz 返回 replies 为回帖数，不含主楼，故这里使用 <= 保守判断。
  bool get hasMore {
    if (nextPageUrl != null) {
      return true;
    }
    final knownLastPage = lastPage;
    if (knownLastPage != null) {
      return currentPage < knownLastPage;
    }
    final loaded = currentPage * perPage;
    return loaded <= replies;
  }

  factory ThreadDetailData.fromVariables(
    JsonMap variables, {
    required int page,
  }) {
    final thread = ParseUtils.asMap(variables['thread']);
    final perPage = ParseUtils.asInt(variables['ppp'], fallback: 20);

    return ThreadDetailData(
      tid: ParseUtils.asString(thread['tid']),
      fid: ParseUtils.asString(
        variables['fid'],
        fallback: ParseUtils.asString(thread['fid']),
      ),
      typeid: ParseUtils.asString(
        thread['typeid'],
        fallback: ParseUtils.asString(variables['typeid']),
      ),
      subject: ParseUtils.asString(thread['subject']),
      author: ParseUtils.asString(thread['author']),
      replies: ParseUtils.asInt(thread['replies']),
      views: ParseUtils.asInt(thread['views']),
      currentPage: page,
      perPage: perPage,
      posts: ParseUtils.asList(
        variables['postlist'],
      ).map((item) => ThreadPost.fromJson(ParseUtils.asMap(item))).toList(),
    );
  }
}
